# VoxFlow

**Speech-to-text local para Português Europeu (PT-PT) e English.**  
100% grátis. 100% privado. macOS 14+ / Apple Silicon.

## Features

- **Whisper large-v3-turbo** para EN (~3-4% WER)
- **inesc-id fine-tuned** para PT-PT (~12.5% WER — melhor modelo grátis)
- **Groq Llama 3.3 70B** para polish (300+ tok/s, 14,400 req/dia grátis)
- **Auto-paste** no cursor com clipboard restore
- **Power Mode** — adapta tom por app (Email=formal, Slack=casual, Code=técnico)
- **Menu bar app** nativa SwiftUI
- **Hotkey ⌥+Space** global
- **Waveform animada** durante gravação
- **Histórico pesquisável** com estatísticas
- **Onboarding wizard** na primeira utilização
- **Hold-to-talk** mode
- **0 MB RAM idle** — modelo carrega on-demand
- **Sons de feedback** (início/fim/erro)
- **Auto-detect microfone** (filtra virtuais Zoom/Teams)

## Instalação

### Requisitos
- macOS 14+ (Sonoma/Tahoe)
- Apple Silicon (M1+)
- Xcode 15+ (para compilar)
- `brew install whisper-cpp ffmpeg`

### Build
```bash
git clone https://github.com/SEU_USER/VoxFlow.git
cd VoxFlow
swift build
```

### Instalar
```bash
# Criar .app bundle
mkdir -p /Applications/VoxFlow.app/Contents/MacOS
cp .build/debug/VoxFlow /Applications/VoxFlow.app/Contents/MacOS/
cp Info.plist /Applications/VoxFlow.app/Contents/
codesign --force --sign - /Applications/VoxFlow.app/Contents/MacOS/VoxFlow
open /Applications/VoxFlow.app
```

### Modelos (download automático na primeira utilização)
- `ggml-small.bin` (465 MB) — básico
- `ggml-large-v3-turbo.bin` (1.6 GB) — recomendado
- `inesc-id/WhisperLv3-X-PT-All` (2.9 GB) — melhor PT-PT

### CLI
```bash
vox 5             # grava 5s, transcreve, cola no cursor
vox-ptpt 5        # PT-PT premium (modelo fine-tuned)
vox --stream      # tempo real
vox --settings    # definições
vox --devices     # microfones
```

## Polish (grátis)

1. Vai a [console.groq.com](https://console.groq.com)
2. Cria conta grátis
3. API Keys → Create
4. Na app: Definições → Polish → cola a key

## Benchmarks (M4 16GB)

| Modelo | WER PT-PT | Velocidade | RAM pico |
|--------|-----------|-----------|----------|
| small | ~12% | 1.6s | 465 MB |
| large-v3-turbo | ~8-10% | 2.6s | 1.6 GB |
| inesc-id (PT-PT) | **12.5%** (fine-tuned) | 10-15s | 2.9 GB |

## Licença

MIT
