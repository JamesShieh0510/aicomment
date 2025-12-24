# aicommit - AI-powered Git Commit Messages with Ollama

A zsh function that generates git commit messages using your local Ollama instance, similar to aicommits.

## Features

- 🚀 Automatically generates commit messages from staged changes
- 🤖 Uses local Ollama models (no API keys needed)
- ⚙️ Configurable via environment variable
- 🔍 Auto-detects available models if not configured
- ✅ Error handling for missing models or Ollama service

## Installation

### Option 1: Use the install script (Recommended)

```bash
./install.sh
source ~/.zshrc
```

### Option 2: Add to .zshrc directly

Copy the function from `aicommit.zshrc` and paste it into your `~/.zshrc` file:

```bash
cat aicommit.zshrc >> ~/.zshrc
source ~/.zshrc
```

### Option 3: Source the script

Add this line to your `~/.zshrc`:

```bash
source /path/to/aicommit.sh
```

## Configuration

### Set Default Model (Optional)

You can set a default model using the `OLLAMA_MODEL` environment variable:

```bash
# Add to ~/.zshrc
export OLLAMA_MODEL="llama2"
```

If `OLLAMA_MODEL` is not set, the function will automatically fetch the first available model from Ollama.

## Usage

1. Stage your changes:
   ```bash
   git add .
   ```

2. Run the function:
   ```bash
   aicommit
   ```

3. Review the suggested commit message and confirm (y/N)

### Optional: Add Prefix

You can add a prefix to the commit message:

```bash
aicommit "feat"
# Will generate: "feat: <generated message>"
```

## Requirements

- zsh shell
- Git
- Ollama running locally (default: http://localhost:11434)
- At least one Ollama model installed
- `curl` command
- `jq` (optional, but recommended for better JSON parsing)

## Error Handling

The function will show helpful error messages for:

- ❌ No staged changes
- ❌ Ollama not running or not accessible
- ❌ No models installed in Ollama
- ❌ Failed API calls

## Example

```bash
$ git add .
$ aicommit
No OLLAMA_MODEL set, fetching available models...
Using model: llama2
Generating commit message...

Suggested commit message:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
feat: add user authentication module
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Do you want to commit with this message? (y/N): y
Committed successfully!
```

## Troubleshooting

### Ollama not found
Make sure Ollama is running:
```bash
ollama serve
```

### No models available
Install a model:
```bash
ollama pull llama2
# or
ollama pull mistral
```

### jq not found
The function will work without `jq`, but it's recommended for better JSON parsing:
```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq
```


# Apple M3 Max (Memory: 128 GB) models
```bash
llama3.3:70b
deepseek-r1:70b
deepseek-r1:8b
gemma3:1b
llama2
qwen3-vl:4b
```