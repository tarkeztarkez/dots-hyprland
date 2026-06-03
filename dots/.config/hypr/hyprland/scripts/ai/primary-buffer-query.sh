#!/usr/bin/env bash

# Default system prompt
SYSTEM_PROMPT="You are a helpful, quick assistant that provides brief and concise explanation \
to given content in at most 100 characters. If the given content is not in English, translate \
it to English. If the content is an English word, provide its meaning. If the content is a name, \
provide some info about it. For a math expression, provide a simplification, \
each step on a line following this style: \`2x=11 (subtract 7 from both sides)\`. \
If you do not know the answer, simply say 'No info available'. \
Only respond for the appropriate case and use as little text as possible.\
The content:"

api_url="${GEMINI_WEBAPI_CHAT_URL:-http://127.0.0.1:8765/v1/chat/completions}"
model="${GEMINI_WEBAPI_MODEL:-gemini-3-flash}"

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --model) model="$2"; shift ;; # Set the model from the flag
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

content=$(wl-paste -p | tr '\n' ' ' | head -c 2000)  # 2000 char limit to prevent overflow

# Make the API call with the specified or default model through local Gemini WebAPI
api_payload=$(jq -n --arg model "$model" --arg system_prompt "$SYSTEM_PROMPT" --arg content "$content" \
    '{model: $model, stream: false, messages: [{role: "system", content: $system_prompt}, {role: "user", content: $content}]}')
response=$(curl -s "$api_url" -H 'Content-Type: application/json' -d "$api_payload" \
    | jq -r '.choices[0].message.content // .error.message // "No info available"' 2>/dev/null)

# Check if content is a single line and no longer than 30 characters
if [[ ${#content} -le 30 && "$content" != *$'\n'* ]]; then
    notify-send --app-name="Text selection query" --expire-time=10000 \
        "$content" "$response"
else
    notify-send --app-name="Text selection query" --expire-time=10000 \
        "AI Response" "$response"
fi
