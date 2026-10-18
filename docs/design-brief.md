# Meety: briefing de design

## O produto

Meety é um app de Mac, gratuito e de código aberto, que grava reuniões (a voz do usuário e o áudio da
chamada, em trilhas separadas), transcreve no próprio Mac (Apple Silicon, modelo Whisper na GPU),
separa quem falou e gera resumos ou atas. Nada sai do computador, a não ser que a pessoa escolha um
resumo na nuvem (Claude, ChatGPT ou chave de API). Público: qualquer pessoa que participa de
reuniões (advogados, consultores, estudantes, equipes), sem conhecimento técnico. Download pelo
GitHub como DMG. Interface em inglês (padrão) e português.

Nome: **Meety**. Feito pela **Oka** (startup de IA). Tom: sóbrio, direto, acolhedor, sem jargão.
Promessa em uma linha: "Record, transcribe and summarize your meetings. Entirely on your Mac."

## Plataforma e restrições

- macOS 15+, app nativo em **SwiftUI**. O design deve caber nos componentes nativos do Mac
  (NavigationSplitView com barra lateral e detalhe, toolbar, Form de ajustes, sheets, popovers,
  menus). Nada de web view.
- Precisa funcionar em **tema claro e escuro** e com a cor de destaque do sistema ou uma própria.
- Ícones: preferir **SF Symbols**. Ícone do app: macOS (quadrado arredondado), 1024 px.
- Textos curtos e claros; o app é bilíngue, então os rótulos crescem ~30% em português.
- Janela mínima 820×520; tamanho padrão 1100×700. Barra lateral entre 260 e 420 pt.
- Também vive na **barra de menus** (ícone pequeno; menu com Iniciar/Parar gravação, tempo
  decorrido, Abrir o Meety, Ajustes, Sair).

## Mapa de telas (o que existe hoje, funcional e sem design)

### 1. Boas-vindas (sheet 560×460, 4 passos, pontos de progresso embaixo, botões Voltar / Continuar)
1. **Welcome to Meety**: ícone grande, título, parágrafo "Record your meetings, get a transcript you
   can search, and a summary you can share. Everything runs on your Mac: your conversations stay
   with you." e a linha "Two quick permissions and one download, then you're set."
2. **Microphone**: ícone mic, explicação ("So Meety can hear you. Your voice is recorded on its own
   track, which is how Meety knows which lines are yours."), botão "Allow microphone"; depois vira
   selo verde "Allowed".
3. **System audio**: explica que o macOS agrupa em "Screen & System Audio Recording" e que o Meety
   não grava a tela; botão "Open System Settings"; aviso de que pode precisar reabrir o app.
4. **Download the models**: texto com a memória do Mac ("Meety picked the right sizes for this Mac
   (24 GB of memory)..."), lista de 3 modelos recomendados (Transcription / Summaries / Speakers,
   cada um com nome, selo "Recommended", tamanho, botão Download ou barra de progresso e check
   verde), botão grande "Download recommended (4.0 GB)", nota de que pode continuar usando o app.
   Botão final "Start using Meety".

### 2. Janela principal
- **Barra lateral**: no topo, o **bloco de gravar**: botão redondo vermelho (vira quadrado de parar
  durante a gravação), título "Record" e subtítulo "Your voice and the call audio"; durante a
  gravação mostra o tempo (00:12:34) e dois medidores de nível ("You" e "Others"); à direita, um
  seletor de microfone. Abaixo, campo de busca "Search meetings" e a **lista de reuniões**: título,
  data e hora, duração, ícone de documento quando foi importada; bolinha vermelha na que está
  gravando; spinner na que está transcrevendo; triângulo laranja quando falhou. Menu de contexto:
  Show in Finder, Transcribe (again), Move to Trash.
- **Toolbar**: botão Import (arquivo de áudio/vídeo); na reunião aberta, Export e menu "…"
  (Transcribe again, Show in Finder, Move to Trash).
- **Detalhe vazio**: ícone, "Record a meeting or drop a file here", frase de privacidade, botões
  Record (vermelho) e "Import file…". Arrastar um arquivo sobre a janela mostra uma borda
  tracejada com "Drop to transcribe".
- **Detalhe de uma reunião**: cabeçalho com título editável (grande), linha com data por extenso,
  duração, idioma; **tocador** (voltar 15 s, play/pause, avançar 15 s, tempo atual, slider, tempo
  total, velocidade 1×/1,25×/1,5×/2×); segmentado **Transcript | Summary**.
  - **Transcript**: legenda de falantes no topo (chips coloridos com nome, clicáveis para renomear:
    popover "Who is this?" com campo e botão Rename), depois blocos por falante: nome colorido +
    carimbo de tempo, parágrafo corrido; a frase que está tocando fica destacada; clicar numa frase
    pula o áudio. Falantes padrão: "You", "Participant 1, 2…" (gravações) ou "Speaker 1, 2…"
    (arquivos importados).
  - **Summary**: à esquerda, controles: "What do you need" (Short summary, Meeting minutes, Action
    items, Custom prompt, com ícones) e "Written by" (Apple Intelligence, Local model, Claude,
    ChatGPT (Codex), API key; os indisponíveis aparecem com "not ready" e uma frase laranja com
    botão de ação: Download, Open app, Add key); botão Generate (vira Stop); linha com ícone de
    cadeado (local) ou nuvem (sai do Mac) e a descrição do provedor. Abaixo, o texto gerado em
    Markdown (editável depois de salvo) com botões copiar e apagar. À direita, lista "Saved
    summaries" (tipo e data). Alerta antes do primeiro uso na nuvem: "Send the transcript to the
    cloud?".
  - **Estados**: reunião **gravando** (ícone de onda vermelho animado, tempo grande, "Recording.
    Press stop when the meeting ends.", botão Stop); **transcrevendo** (barra de progresso,
    etapa: Preparing audio… / Loading model… / Transcribing… / Telling speakers apart… / Saving…,
    "42% · about 01:10 left", botão Cancel); **não transcrita** (ícone, "Not transcribed yet",
    botão Transcribe); **falhou** (triângulo, mensagem em linguagem simples, botão Transcribe).
- **Export** (sheet 480 pt): título, radio com formatos (Plain text, Markdown, Subtitles SRT,
  Subtitles VTT, JSON), prévia monoespaçada, botões Copy, Cancel, Save….

### 3. Ajustes (janela 560 pt, abas)
- **General**: idioma da reunião (Detect automatically / lista), "Tell speakers apart", "Transcribe
  automatically when a recording ends", seção Permissions (Microphone, Screen & System Audio
  Recording, com estado Allowed/Not allowed e botão Open), seção Library (Show in Finder, tamanho).
- **Models**: três seções (Transcription, Local summaries, Speakers), cada uma com picker "Use" e a
  lista de modelos (nome, selo Recommended/Most accurate/Light, descrição, tamanho, Download /
  progresso / check verde + lixeira). Linha "Space used by models".
- **Summaries**: idioma do resumo (Same as Meety / Same as the meeting); seção "Claude and ChatGPT
  on this Mac" com o estado de cada CLI (encontrado pelo terminal / pelo app, ou Not found); seção
  API key (Provider Anthropic/OpenAI, campo de senha, Save key, link Get a key).
- **About**: versão, motor (Python/MLX/chip), memória, "Export diagnostics…", link GitHub, "Meety is
  free and open source. Made by Oka."

### 4. Barra de menus
Ícone (onda + mic; vira círculo vermelho ao gravar). Menu: "Start recording" ⇧⌘R (ou "Recording ·
00:12:34" + "Stop recording"), Open Meety, Settings…, Quit Meety.

## O que eu gostaria de receber

1. **Identidade**: ícone do app (1024 px, estilo macOS), paleta (claro e escuro) com cor de
   destaque e cores para até 8 falantes, tipografia (pode ser a do sistema), tom das ilustrações
   ou ícones de estado vazio.
2. **Telas** em alta fidelidade, claro e escuro: boas-vindas (os 4 passos), janela principal vazia,
   principal com transcrição (falantes coloridos), estado gravando, estado transcrevendo, aba
   Summary, sheet de exportação, Ajustes > Models, menu da barra de menus.
3. **Componentes** reutilizáveis: bloco de gravar com medidores, linha de reunião na lista, chip de
   falante, linha de modelo com progresso, card de provedor de resumo, estados vazios.
4. Export em PNG e, se possível, os tokens (cores, raios, espaçamentos) em texto ou JSON para eu
   aplicar no SwiftUI.
