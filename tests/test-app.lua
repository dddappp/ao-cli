-- Simple AO Test Application for ao-cli testing
-- This app provides basic handlers to test all ao-cli commands

-- Initialize json library
json = require('json')

-- Initialize state
State = State or {}
State.counter = State.counter or 0
State.messages = State.messages or {}
State.test_data = State.test_data or {}

-- Helper function to send response
function sendResponse(data, tags)
    ao.send({
        Target = ao.id,
        Tags = tags or {},
        Data = data
    })
end

-- Handler for basic message test
Handlers.add(
    "TestMessage",
    Handlers.utils.hasMatchingTag("Action", "TestMessage"),
    function(msg)
        print("🔍 TestMessage handler: Processing message with data: " .. msg.Data)
        State.counter = State.counter + 1
        print("📊 Counter incremented to: " .. State.counter)
        local response = {
            success = true,
            counter = State.counter,
            received_data = msg.Data,
            timestamp = os.time()
        }
        print("📤 Sending response with received_data: " .. msg.Data)
        sendResponse(json.encode(response), { Action = "TestMessageResponse" })
        print("✅ TestMessage handler completed")
    end
)

-- Handler for data manipulation test
Handlers.add(
    "SetData",
    Handlers.utils.hasMatchingTag("Action", "SetData"),
    function(msg)
        local data = json.decode(msg.Data)
        State.test_data[data.key] = data.value
        local response = {
            success = true,
            key = data.key,
            value = data.value,
            all_data = State.test_data
        }
        sendResponse(json.encode(response), { Action = "SetDataResponse" })
    end
)

-- Handler for data retrieval test
Handlers.add(
    "GetData",
    Handlers.utils.hasMatchingTag("Action", "GetData"),
    function(msg)
        local key = msg.Data
        local response = {
            success = true,
            key = key,
            value = State.test_data[key] or "not_found",
            all_data = State.test_data
        }
        sendResponse(json.encode(response), { Action = "GetDataResponse" })
    end
)

-- Handler for error testing
Handlers.add(
    "TestError",
    Handlers.utils.hasMatchingTag("Action", "TestError"),
    function(msg)
        error("Test error: " .. (msg.Data or "no message"))
    end
)

-- Handler for inbox test (sends message to self)
Handlers.add(
    "TestInbox",
    Handlers.utils.hasMatchingTag("Action", "TestInbox"),
    function(msg)
        ao.send({
            Target = ao.id,
            Tags = { Action = "InboxTestReply" },
            Data = json.encode({
                original_message = msg.Data,
                timestamp = os.time(),
                inbox_length_before = #Inbox
            })
        })
    end
)

-- Handler for inbox reply
Handlers.add(
    "InboxTestReply",
    Handlers.utils.hasMatchingTag("Action", "InboxTestReply"),
    function(msg)
        -- This handler just processes the reply, no response needed
        -- The inbox will contain this message
    end
)

-- Default handler for unknown actions
Handlers.add(
    "UnknownAction",
    function(msg)
        return msg.Action ~= nil
    end,
    function(msg)
        sendResponse(json.encode({
            error = "Unknown action",
            action = msg.Action,
            data = msg.Data
        }), { Action = "ErrorResponse" })
    end
)
