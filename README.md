# VoxFlow

Menu bar app para ditado e transcricao em Portugues Europeu (PT-PT) no macOS.

## Setup recomendado

- **Transcricao final:** OpenAI `gpt-4o-transcribe`
- **Preview live:** OpenAI `gpt-realtime-whisper`
- **Polish PT-PT:** OpenAI `gpt-5.5`
- **Fallback local/offline:** `whisper.cpp` com `large-v3-turbo`
- **Aprendizagem:** glossario local + correccoes guardadas, usadas nos prompts seguintes

Este setup privilegia qualidade PT-PT. Para poupar custo, usa `gpt-4o-mini-transcribe` e `gpt-5.4-mini`, ou desactiva o polish.

## Funcionalidades

- Captura nativa de audio no macOS
- Hotkey global `Option + Space`
- Transcricao OpenAI ou local
- Preview live opcional durante a gravacao
- Fallback local visivel se a API falhar
- Vocabulario personalizado para nomes, marcas e termos tecnicos
- Memoria local de correccoes
- Polish por contexto da app activa
- Auto-paste no cursor
- Historico pesquisavel e estimativa de custo
- API keys guardadas no Keychain

## Requisitos

- macOS 14+
- Apple Silicon recomendado
- Xcode 15+ para compilar
- Para fallback local: `brew install whisper-cpp`

O fallback local procura modelos em:

```text
~/Library/Application Support/VoxFlow/Models/
```

Exemplo:

```text
~/Library/Application Support/VoxFlow/Models/ggml-large-v3-turbo.bin
```

## Build

```bash
swift build
swift test
```

No Codex, usa a acao **Run**. Em terminal:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

## Configuracao na app

1. Abre `Definicoes > Modelo`.
2. Escolhe `OpenAI - melhor qualidade PT-PT`.
3. Cola a OpenAI API key.
4. Usa `gpt-4o-transcribe` para melhor qualidade.
5. Mantem `Preview live com gpt-realtime-whisper` activo se quiseres texto durante a fala.
6. Em `Definicoes > Polish`, escolhe `OpenAI - gpt-5.5`.
7. Adiciona nomes e termos em `Vocabulario personalizado`.
8. Depois de cada transcricao, corrige o texto e carrega em `Guardar correcao`.

## Publicacao da landing

Este repo inclui uma landing estatica em `public/` para Vercel. E intencionalmente
**bring your own key**:

- o site nao tem backend;
- nenhuma API key fica no Vercel;
- cada utilizador cola a sua key dentro da app macOS;
- a app guarda a key no Keychain local.

Deploy recomendado:

```bash
vercel link
vercel --prod
vercel domains add aitipro.com
```

O `vercel.json` serve apenas `public/`, por isso o deploy web nao publica os
ficheiros Swift como assets do site.

## Custos

Regra pratica para qualidade maxima:

```text
gpt-4o-transcribe + gpt-5.5 ~= $0.02/min
```

Com preview realtime activo, a estimativa sobe. Define sempre um limite mensal na dashboard da OpenAI.

## Privacidade

- Modo local: audio e texto ficam no Mac.
- Modo OpenAI: audio/texto sao enviados para a OpenAI para transcricao/polish.
- API keys sao guardadas no Keychain do macOS.
- Historico e correccoes ficam em `~/.voxflow/`.

## Verificacao

```bash
swift test
swift build
```

## Licenca

MIT
