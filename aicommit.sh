#!/bin/zsh

# aicommit function - Generate commit messages using Ollama
# Usage: aicommit [optional commit message prefix]

aicommit() {
    # Check if there are any staged changes
    if git diff --cached --quiet; then
        echo "No staged changes found. Please run 'git add' first."
        return 1
    fi

    # Get the diff of staged changes
    local staged_diff=$(git diff --cached)
    
    if [ -z "$staged_diff" ]; then
        echo "No staged changes to commit."
        return 1
    fi

    # Get model from environment variable or fetch from Ollama
    local model="${OLLAMA_MODEL:-}"
    
    if [ -z "$model" ]; then
        echo "No OLLAMA_MODEL set, fetching available models..."
        
        # Check if Ollama is running
        if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
            echo "Error: Ollama is not running or not accessible at http://localhost:11434"
            echo "Please start Ollama or check your connection."
            return 1
        fi
        
        # Fetch available models
        local models_json=$(curl -s http://localhost:11434/api/tags)
        
        if [ -z "$models_json" ] || [ "$models_json" = "null" ]; then
            echo "Error: Failed to fetch models from Ollama."
            return 1
        fi
        
        # Extract first model name using jq if available, otherwise use grep/sed
        if command -v jq > /dev/null 2>&1; then
            model=$(echo "$models_json" | jq -r '.models[0].name // empty' 2>/dev/null)
        else
            # Fallback: extract first model name using grep/sed
            model=$(echo "$models_json" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"\([^"]*\)"/\1/')
        fi
        
        if [ -z "$model" ] || [ "$model" = "null" ]; then
            echo "Error: No models found in Ollama. Please install a model first."
            echo "Example: ollama pull llama2"
            return 1
        fi
        
        echo "Using model: $model"
    else
        echo "Using model from OLLAMA_MODEL: $model"
    fi

    # Prepare the prompt for Ollama
    local prompt="Generate a concise git commit message based on the following diff. 
The commit message should follow conventional commit format if applicable.
Only return the commit message, no explanations.

\`\`\`diff
${staged_diff}
\`\`\`"

    # Call Ollama API to generate commit message using streaming API for faster response
    echo "Generating commit message..."
    
    # Create JSON payload with streaming enabled
    local json_payload
    if command -v jq > /dev/null 2>&1; then
        json_payload=$(jq -n \
            --arg model "$model" \
            --arg prompt "$prompt" \
            '{model: $model, prompt: $prompt, stream: true}')
    else
        # Fallback: manual JSON construction (basic escaping)
        local escaped_prompt=$(echo "$prompt" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
        json_payload="{\"model\":\"${model}\",\"prompt\":\"${escaped_prompt}\",\"stream\":true}"
    fi
    
    # Set timeout (default 120 seconds for streaming, can be overridden with OLLAMA_TIMEOUT env var)
    # Some models like gpt-oss:20b may need more time
    local timeout_seconds="${OLLAMA_TIMEOUT:-120}"
    
    # Use streaming API - collect all response chunks
    local response=""
    local commit_msg=""
    
    # Use curl with streaming, collecting all JSON lines
    # Note: curl exit code 28 means timeout, but we may still have partial response
    if command -v gtimeout > /dev/null 2>&1; then
        # macOS with GNU coreutils
        response=$(gtimeout ${timeout_seconds}s curl -s -N http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d "$json_payload" 2>&1)
    elif command -v timeout > /dev/null 2>&1; then
        # Linux timeout command
        response=$(timeout ${timeout_seconds}s curl -s -N http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d "$json_payload" 2>&1)
    else
        # macOS fallback: use curl's --max-time option
        response=$(curl -s -N --max-time ${timeout_seconds} http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d "$json_payload" 2>&1)
    fi
    
    local curl_exit_code=$?
    
    # Check for timeout (exit code 28) - but continue if we have partial response
    if [ $curl_exit_code -eq 28 ]; then
        if [ -z "$response" ]; then
            echo "Error: Request timed out after ${timeout_seconds} seconds with no response."
            echo "You can increase the timeout by setting OLLAMA_TIMEOUT environment variable."
            echo "Example: export OLLAMA_TIMEOUT=300  # 5 minutes"
            return 1
        else
            echo "Warning: Request timed out, but using partial response..."
        fi
    fi
    
    if [ -z "$response" ] && [ $curl_exit_code -ne 28 ]; then
        echo "Error: Failed to generate commit message from Ollama."
        if [ $curl_exit_code -ne 0 ]; then
            echo "Curl exit code: $curl_exit_code"
        fi
        return 1
    fi
    
    # Parse streaming response - extract response field from each JSON line and concatenate
    # Note: Some models return "thinking" field first, then "response"
    if command -v jq > /dev/null 2>&1; then
        # Extract only non-empty response fields, ignore thinking
        commit_msg=$(echo "$response" | jq -r 'select(.response != null and .response != "") | .response' 2>/dev/null | tr -d '\n')
    elif command -v python3 > /dev/null 2>&1; then
        commit_msg=$(echo "$response" | python3 -c "
import sys
import json

full_response = ''
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        # Only collect non-empty response fields, ignore thinking
        if 'response' in data and data['response']:
            full_response += data['response']
    except:
        pass
print(full_response, end='')
" 2>/dev/null)
    else
        # Fallback: extract response using sed/grep
        # Only match non-empty response fields
        commit_msg=$(echo "$response" | grep -o '"response":"[^"]*"' | sed 's/"response":"\([^"]*\)"/\1/g' | grep -v '^$' | tr -d '\n' | sed 's/\\n/\n/g' | sed 's/\\"/"/g' | sed 's/\\\\/\\/g')
    fi
    
    # If streaming parse failed, commit_msg will be empty and we'll fall through to the fallback parsing below
    
    # Check if we already extracted commit_msg from streaming response
    if [ -z "$commit_msg" ]; then
        # Debug: check if response contains error (only if we have actual error message)
        if echo "$response" | grep -q '"error"'; then
            local error_msg=$(echo "$response" | grep -o '"error":"[^"]*"' | head -1 | sed 's/"error":"\([^"]*\)"/\1/')
            if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
                echo "Error from Ollama: $error_msg"
                return 1
            fi
        fi
        
        # If we timed out and have no response content, check if we only got thinking fields
        if [ $curl_exit_code -eq 28 ] && echo "$response" | grep -q '"thinking"'; then
            echo "Warning: Model is still thinking. Response may be incomplete."
            echo "Consider increasing OLLAMA_TIMEOUT for this model."
        fi
    
    # Extract the response text
    # Ollama API returns response in 'response' field
    local commit_msg=""
    local parse_error=""
    local parser_used=""
    
    # Try jq first (best option)
    if command -v jq > /dev/null 2>&1; then
        parser_used="jq"
        commit_msg=$(echo "$response" | jq -r '.response // empty' 2>&1)
        local jq_exit=$?
        if [ $jq_exit -ne 0 ] || [ -z "$commit_msg" ]; then
            parse_error="jq parsing failed (exit: $jq_exit)"
            commit_msg=""
        fi
    fi
    
    # Try Python3 if jq failed or not available
    # Force check for python3 explicitly
    if [ -z "$commit_msg" ]; then
        if command -v python3 > /dev/null 2>&1; then
            parser_used="python3"
            # Use python3 with proper JSON handling
            # Write response to temp file to avoid shell escaping issues
            temp_json=$(mktemp)
            # Write response to temp file, ensuring proper encoding
            printf '%s' "$response" > "$temp_json"
            commit_msg=$(python3 <<PYTHON_EOF
import sys
import json
import os
import re

temp_file = '$temp_json'
try:
    # Read file as binary first, then decode to handle any encoding issues
    with open(temp_file, 'rb') as f:
        content = f.read()
    
    # Try to decode as UTF-8, with error handling
    try:
        text = content.decode('utf-8')
    except UnicodeDecodeError:
        # Fallback to latin-1 which can decode any byte
        text = content.decode('latin-1')
    
    # Try to parse JSON normally first
    try:
        data = json.loads(text)
        response = data.get('response', '')
        if response:
            sys.stdout.write(response)
            sys.stdout.flush()
    except json.JSONDecodeError as e:
        # If JSON decode fails due to control characters, try manual extraction
        # Look for "response":"..." pattern, handling escaped characters
        # This regex handles escaped quotes and newlines
        pattern = r'"response"\s*:\s*"((?:[^"\\\\]|\\\\.)*)"'
        match = re.search(pattern, text, re.DOTALL)
        if match:
            import codecs
            response_str = match.group(1)
            # Decode escape sequences
            response = codecs.decode(response_str, 'unicode_escape')
            sys.stdout.write(response)
            sys.stdout.flush()
        else:
            # Try simpler pattern without escaped characters
            pattern2 = r'"response"\s*:\s*"([^"]*)"'
            match2 = re.search(pattern2, text)
            if match2:
                sys.stdout.write(match2.group(1))
                sys.stdout.flush()
            else:
                sys.stderr.write(f"JSON decode error: {e}")
                sys.exit(1)
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
PYTHON_EOF
            2>/dev/null)
            py_exit=$?
            rm -f "$temp_json"
            
            if [ $py_exit -ne 0 ] || [ -z "$commit_msg" ]; then
                # Get the actual error message
                temp_json2=$(mktemp)
                echo "$response" > "$temp_json2"
                py_error=$(python3 <<PYTHON_EOF
import sys
import json
import os

temp_file = '$temp_json2'
try:
    with open(temp_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    sys.stdout.write(data.get('response', ''))
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
PYTHON_EOF
                2>&1)
                rm -f "$temp_json2"
                parse_error="python3 parsing failed (exit: $py_exit)"
                if [ -n "$py_error" ] && echo "$py_error" | grep -q -v "^$" && ! echo "$py_error" | grep -q "Traceback"; then
                    parse_error="$parse_error - $(echo "$py_error" | head -1 | cut -c1-100)"
                fi
                commit_msg=""
            fi
        fi
    fi
    
    # Try Python 2 as last resort (but prefer python3)
    if [ -z "$commit_msg" ] && command -v python > /dev/null 2>&1; then
        parser_used="python"
        commit_msg=$(echo "$response" | python -c "
import sys
import json
try:
    data = json.load(sys.stdin)
    response = data.get('response', '')
    if response:
        sys.stdout.write(response)
        sys.stdout.flush()
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
" 2>/dev/null)
        local py_exit=$?
        if [ $py_exit -ne 0 ] || [ -z "$commit_msg" ]; then
            parse_error="python parsing failed (exit: $py_exit)"
            commit_msg=""
        fi
    fi
    
    if [ -z "$parser_used" ]; then
        parse_error="no JSON parser available (jq/python)"
    fi
    
    # If parsing failed or result is empty, try sed fallback
    if [ -z "$commit_msg" ] || [ "$commit_msg" = "null" ]; then
        # Use a more robust sed approach: extract everything between "response":" and ","done"
        # This handles multi-line responses better
        commit_msg=$(echo "$response" | sed -n 's/.*"response":"\(.*\)","done".*/\1/p')
        
        # If that fails, try extracting up to the next field
        if [ -z "$commit_msg" ]; then
            # Extract from "response":" to the next ","
            commit_msg=$(echo "$response" | sed -n 's/.*"response":"\([^"]*\)".*/\1/p')
        fi
        
        # Handle escaped characters
        if [ -n "$commit_msg" ]; then
            commit_msg=$(echo "$commit_msg" | sed 's/\\n/\n/g' | sed 's/\\"/"/g' | sed 's/\\\\/\\/g' | sed 's/\\r//g' | sed 's/\\t/\t/g')
        fi
    fi
    
    if [ -z "$commit_msg" ] || [ "$commit_msg" = "null" ]; then
        # If we timed out and only got thinking fields, provide helpful message
        if [ $curl_exit_code -eq 28 ] && echo "$response" | grep -q '"thinking"'; then
            echo "Error: Model timed out while thinking. No response generated yet."
            echo ""
            echo "This model (gpt-oss:20b) may need more time to process."
            echo "Try increasing the timeout:"
            echo "  export OLLAMA_TIMEOUT=300  # 5 minutes"
            echo "  aicommit"
            return 1
        fi
        
        echo "Error: Failed to parse response from Ollama."
        if [ -n "$parser_used" ]; then
            echo "Parser attempted: $parser_used"
        fi
        if [ -n "$parse_error" ]; then
            echo "Parse error: $parse_error"
        fi
        echo "Debug: Response preview (first 300 chars):"
        echo "$response" | head -c 300
        echo ""
        echo ""
        echo "Troubleshooting:"
        echo "  1. Install jq for better parsing: brew install jq"
        echo "  2. Check if python3 is available: which python3"
        echo "  3. Verify Ollama response format"
        return 1
    fi
    fi  # End of if [ -z "$commit_msg" ] block for fallback parsing
    
    # Clean up the commit message (remove leading/trailing whitespace, newlines)
    commit_msg=$(echo "$commit_msg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
    
    # If user provided a prefix, prepend it
    if [ -n "$1" ]; then
        commit_msg="$1: $commit_msg"
    fi
    
    echo ""
    echo "Suggested commit message:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$commit_msg"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Ask user if they want to commit
    read "?Do you want to commit with this message? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        git commit -m "$commit_msg"
        echo "Committed successfully!"
    else
        echo "Commit cancelled."
    fi
}

