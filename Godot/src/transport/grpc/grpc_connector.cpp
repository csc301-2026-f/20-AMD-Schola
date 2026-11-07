// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "transport/grpc/grpc_connector.h"

#include "transport/grpc/training_messages.h"

#include "GymConnector.grpc.pb.h"

#include <condition_variable>
#include <mutex>
#include <optional>
#include <string>
#include <utility>

// How a call travels
// ==================
//
// Python's client is synchronous: it sends one call and blocks until it gets
// the answer. gRPC runs each call's handler on one of its own worker threads,
// but only Godot's main thread may touch the game. So a call is handed over:
//
//   gRPC worker thread (Service)             Godot main thread (GrpcConnector)
//   ----------------------------             ---------------------------------
//   UpdateState arrives
//   post it as the pending call  --------->  wait_for_update() takes it,
//   wait...                                  ConnectorLoop runs the backend
//                                <---------  reply_step() answers it
//   return the answer to Python
//
// Both sides share the Service's mutex and condition variable. There is only
// ever one pending call, because Python never sends the next one before the
// previous one is answered.
//
// When the session ends (fail(), close(), or Python hanging up), `ended`
// records why. Every waiter on either side wakes up, sees it, and returns,
// so nothing can block forever.

namespace schola {

namespace {

// Python allows messages up to 100 MB each way. gRPC's own receive limit is
// 4 MB, which large observations (cameras) would exceed.
constexpr int MAX_MESSAGE_BYTES = 100 * 1024 * 1024;

// A gRPC thread cannot be woken by Python hanging up, so a waiting handler
// checks for that this often.
constexpr std::chrono::milliseconds HANG_UP_CHECK_INTERVAL{ 100 };

// Waiting handlers return as soon as `ended` is set, so shutdown is quick.
// After this long gRPC cancels whatever is left.
constexpr std::chrono::seconds SHUTDOWN_DEADLINE{ 2 };

enum class CallKind {
	START,
	UPDATE,
};

const char *rpc_name(CallKind p_kind) {
	return p_kind == CallKind::START ? "StartGymConnector" : "UpdateState";
}

// A call from Python that is waiting for the main thread to answer it.
struct PendingCall {
	CallKind kind = CallKind::START;

	// The request, copied off the gRPC thread. Only the field matching `kind` is used.
	::Schola::GymConnectorStartRequest start;
	::Schola::StateUpdate update;

	// Set by the main thread once it starts working on this call.
	bool taken = false;

	// Set by the main thread when it answers. `reply` is UpdateState's response.
	std::optional<grpc::Status> answer;
	::Schola::State reply;
};

} // namespace

/**
 * The gRPC side of the connector, plus the state both threads share.
 *
 * The three handlers below run on gRPC worker threads. They only copy
 * requests in and answers out; the main thread does all conversion and all
 * work on the game.
 */
class GrpcConnector::Service final : public ::Schola::GymService::Service {
public:
	// Guards everything below. `changed` is notified whenever any of it changes.
	std::mutex mutex;
	std::condition_variable changed;

	std::optional<PendingCall> call;

	// Set once StartGymConnector has been answered successfully.
	bool started = false;

	// The definition as Python receives it. Set by publish_definition().
	std::optional<::Schola::TrainingDefinition> definition_message;

	// Why the session can no longer continue. The first reason wins.
	std::optional<Status> ended;

	// The same definition in core types, for converting actions and states.
	// Written and read only on the main thread, so it needs no lock.
	TrainingDefinition definition;

	grpc::Status StartGymConnector(grpc::ServerContext *p_context, const ::Schola::GymConnectorStartRequest *p_request,
			::Schola::GymConnectorStartResponse * /* empty */) override {
		std::unique_lock<std::mutex> lock(mutex);
		if (started) {
			return refuse(CallKind::START, "StartGymConnector was already called for this session.");
		}

		PendingCall pending;
		pending.kind = CallKind::START;
		pending.start = *p_request;
		return hand_to_main_thread(lock, p_context, std::move(pending), nullptr);
	}

	grpc::Status RequestTrainingDefinition(grpc::ServerContext *p_context, const ::Schola::TrainingDefinitionRequest * /* empty */,
			::Schola::TrainingDefinition *r_response) override {
		std::unique_lock<std::mutex> lock(mutex);

		// Python asks right after its start is answered, which can be before the
		// main thread has asked the backend for the definition. Wait for it
		// rather than fail.
		bool published = wait_on_grpc_thread(lock, p_context, [this] { return definition_message.has_value(); });
		if (!published) {
			return to_grpc_status(*ended, "RequestTrainingDefinition");
		}
		*r_response = *definition_message;
		return grpc::Status::OK;
	}

	grpc::Status UpdateState(grpc::ServerContext *p_context, const ::Schola::StateUpdate *p_request,
			::Schola::State *r_response) override {
		std::unique_lock<std::mutex> lock(mutex);

		// The main thread only waits for updates once it has published the
		// definition. Before that, an update would sit unanswered.
		if (!definition_message) {
			return refuse(CallKind::UPDATE, "UpdateState arrived before the training definition was published.");
		}

		PendingCall pending;
		pending.kind = CallKind::UPDATE;
		pending.update = *p_request;
		return hand_to_main_thread(lock, p_context, std::move(pending), r_response);
	}

	/**
	 * Main thread: waits until Python's next call of p_kind arrives and marks
	 * it taken.
	 *
	 * Out: TIMEOUT with p_timeout_message after p_timeout (zero waits until the
	 *      session ends). The ending reason if the session ended first.
	 */
	Status take_call(std::unique_lock<std::mutex> &p_lock, CallKind p_kind, std::chrono::milliseconds p_timeout,
			const std::string &p_timeout_message) {
		auto arrived = [&] { return ended || (call && call->kind == p_kind && !call->taken); };

		if (p_timeout.count() == 0) {
			changed.wait(p_lock, arrived);
		} else if (!changed.wait_for(p_lock, p_timeout, arrived)) {
			return Status::error(StatusCode::TIMEOUT, p_timeout_message);
		}

		if (ended) {
			return *ended;
		}
		call->taken = true;
		return Status::ok();
	}

	/**
	 * Main thread: answers the call it took, waking the gRPC thread waiting on it.
	 *
	 * Out: the ending reason if Python gave up on the call in the meantime.
	 */
	Status answer(CallKind p_kind, grpc::Status p_answer, ::Schola::State p_reply = {}) {
		if (!call || !call->taken || call->kind != p_kind || call->answer) {
			if (ended) {
				return *ended;
			}
			return Status::error(StatusCode::FAILED_PRECONDITION,
					std::string("There is no ") + rpc_name(p_kind) + " call waiting for an answer.");
		}
		call->answer = std::move(p_answer);
		call->reply = std::move(p_reply);
		changed.notify_all();
		return Status::ok();
	}

	/** Records why the session ended, unless it already had, and wakes every waiter. */
	void end(const Status &p_reason) {
		if (!ended) {
			ended = p_reason;
		}
		changed.notify_all();
	}

private:
	grpc::Status refuse(CallKind p_kind, const std::string &p_message) {
		return to_grpc_status(Status::error(StatusCode::FAILED_PRECONDITION, p_message), rpc_name(p_kind));
	}

	/**
	 * gRPC thread: posts p_call, blocks until the main thread answers it, then
	 * copies the answer out to Python.
	 */
	grpc::Status hand_to_main_thread(std::unique_lock<std::mutex> &p_lock, grpc::ServerContext *p_context,
			PendingCall p_call, ::Schola::State *r_response) {
		const char *rpc = rpc_name(p_call.kind);
		if (ended) {
			return to_grpc_status(*ended, rpc);
		}
		if (call) {
			return refuse(p_call.kind, "Another call is still being answered. Schola's Python client sends one call at a time.");
		}

		call = std::move(p_call);
		changed.notify_all();

		bool answered = wait_on_grpc_thread(p_lock, p_context, [this] { return call->answer.has_value(); });
		grpc::Status result = answered ? *call->answer : to_grpc_status(*ended, rpc);
		if (answered && result.ok() && r_response != nullptr) {
			*r_response = std::move(call->reply);
		}

		call.reset();
		changed.notify_all();
		return result;
	}

	/**
	 * gRPC thread: waits until p_done() is true.
	 *
	 * Returns false if the session ended first. If Python hung up, that itself
	 * ends the session, since the call it was waiting on can never be answered.
	 */
	template <typename Done>
	bool wait_on_grpc_thread(std::unique_lock<std::mutex> &p_lock, grpc::ServerContext *p_context, Done p_done) {
		while (!p_done()) {
			if (ended) {
				return false;
			}
			if (p_context->IsCancelled()) {
				end(Status::error(StatusCode::CLOSED, "Python stopped waiting for a reply and disconnected."));
				return false;
			}
			changed.wait_for(p_lock, HANG_UP_CHECK_INTERVAL);
		}
		return true;
	}
};

GrpcConnector::GrpcConnector(GrpcConnectorSettings p_settings) :
		settings(std::move(p_settings)),
		service(std::make_unique<Service>()) {
}

GrpcConnector::~GrpcConnector() {
	close();
}

Status GrpcConnector::open() {
	const std::string address = settings.address + ":" + std::to_string(settings.port);

	grpc::ServerBuilder builder;
	int bound_port = 0;
	// Plain TCP on localhost, the same as Unreal's server.
	builder.AddListeningPort(address, grpc::InsecureServerCredentials(), &bound_port);
	// Linux lets two servers share a port by default. Refusing makes a second
	// Godot instance fail here, instead of both silently taking Python's calls.
	builder.AddChannelArgument(GRPC_ARG_ALLOW_REUSEPORT, 0);
	builder.SetMaxReceiveMessageSize(MAX_MESSAGE_BYTES);
	builder.SetMaxSendMessageSize(MAX_MESSAGE_BYTES);
	builder.RegisterService(service.get());

	server = builder.BuildAndStart();
	if (server == nullptr || bound_port == 0) {
		server.reset();
		return Status::error(StatusCode::RUNTIME_FAILURE,
				"Could not listen for Python on " + address + ". Another program or Godot training session may be using port " +
						std::to_string(settings.port) + "; pass -ScholaPort=<n> to use a different one.");
	}
	return Status::ok();
}

Status GrpcConnector::wait_for_start(StartRequest &r_request, std::chrono::milliseconds p_timeout) {
	std::unique_lock<std::mutex> lock(service->mutex);
	Status status = service->take_call(lock, CallKind::START, p_timeout,
			"Python did not connect to " + settings.address + ":" + std::to_string(settings.port) + " within " +
					std::to_string(p_timeout.count()) + " ms.");
	if (!status.is_ok()) {
		return status;
	}

	// A bad request stays pending: ConnectorLoop passes the error to fail(),
	// which answers Python with it.
	return from_proto(service->call->start, r_request);
}

Status GrpcConnector::reply_start(const Status &p_result) {
	std::lock_guard<std::mutex> lock(service->mutex);
	Status status = service->answer(CallKind::START, to_grpc_status(p_result, "StartGymConnector"));
	if (status.is_ok() && p_result.is_ok()) {
		service->started = true;
	}
	return status;
}

Status GrpcConnector::publish_definition(const TrainingDefinition &p_definition) {
	::Schola::TrainingDefinition message;
	to_proto(p_definition, message);
	service->definition = p_definition;

	std::lock_guard<std::mutex> lock(service->mutex);
	if (service->ended) {
		return *service->ended;
	}
	service->definition_message = std::move(message);
	service->changed.notify_all();
	return Status::ok();
}

Status GrpcConnector::wait_for_update(ConnectorUpdate &r_update, std::chrono::milliseconds p_timeout) {
	std::unique_lock<std::mutex> lock(service->mutex);
	Status status = service->take_call(lock, CallKind::UPDATE, p_timeout,
			"Python sent no UpdateState within " + std::to_string(p_timeout.count()) + " ms.");
	if (!status.is_ok()) {
		return status;
	}

	ConnectorUpdate update;
	status = from_proto(service->call->update, update);

	// Python is leaving, either normally (CLOSE) or after an error of its own
	// (CLOSED status). No reply method follows either, so acknowledge it here.
	// Python's close() waits briefly for this.
	bool python_is_leaving = status.is_ok() ? update.kind == UpdateKind::CLOSE : status.get_code() == StatusCode::CLOSED;
	if (python_is_leaving) {
		// Cannot fail: this thread took the call under the same lock.
		(void)service->answer(CallKind::UPDATE, grpc::Status::OK);
	}

	// Any other bad update stays pending; ConnectorLoop's fail() answers it.
	if (status.is_ok()) {
		r_update = std::move(update);
	}
	return status;
}

Status GrpcConnector::reply_reset(const InitialState &p_initial_state) {
	::Schola::State reply;
	Status status = to_proto(p_initial_state, service->definition, reply);
	if (!status.is_ok()) {
		return status;
	}

	std::lock_guard<std::mutex> lock(service->mutex);
	return service->answer(CallKind::UPDATE, grpc::Status::OK, std::move(reply));
}

Status GrpcConnector::reply_step(const StepResult &p_result) {
	::Schola::State reply;
	Status status = to_proto(p_result, service->definition, reply);
	if (!status.is_ok()) {
		return status;
	}

	std::lock_guard<std::mutex> lock(service->mutex);
	return service->answer(CallKind::UPDATE, grpc::Status::OK, std::move(reply));
}

void GrpcConnector::fail(const Status &p_error) {
	std::lock_guard<std::mutex> lock(service->mutex);

	// Answer whatever Python is waiting on with the error, so it raises it
	// instead of hanging.
	if (service->call && !service->call->answer) {
		service->call->answer = to_grpc_status(p_error, rpc_name(service->call->kind));
	}

	// Every later call is refused with the same error.
	service->end(p_error);
}

void GrpcConnector::close() {
	{
		std::lock_guard<std::mutex> lock(service->mutex);
		service->end(Status::error(StatusCode::CLOSED, "Godot closed the training session."));
	}

	// Unlocked, because the waking handlers need the mutex to return.
	if (server != nullptr) {
		server->Shutdown(std::chrono::system_clock::now() + SHUTDOWN_DEADLINE);
		server->Wait();
		server.reset();
	}
}

} // namespace schola
