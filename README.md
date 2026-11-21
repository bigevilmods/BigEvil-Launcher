# BigEvil Launcher

Biblioteca local de jogos e aplicativos com interface adaptável em português do Brasil, inglês e espanhol. A tela inicial reúne duas galerias horizontais e uma barra de navegação por categoria. A busca encontra itens por nome ou destino. No editor de cada item, você pode importar uma capa local PNG, JPEG ou WebP.

O seletor de idioma na barra superior alterna entre português do Brasil, inglês e espanhol sem reiniciar. O launcher salva a escolha neste dispositivo. A opção **Idioma do sistema** acompanha o sistema, com português do Brasil como padrão para idiomas fora da lista. Os textos cadastrados na biblioteca e o conteúdo de sites são exibidos no idioma de origem.

Selecione a capa de um item para ver a página de detalhes. O editor permite cadastrar a capa, a imagem de fundo, a descrição, o desenvolvedor, a URL do repositório, a URL de download e a URL da versão online. O destino local é opcional. **Baixar** encaminha a URL ao navegador padrão. **Jogar online** abre a versão web dentro do launcher.

O navegador interno usa Android System WebView, Microsoft Edge WebView2 no Windows e WebKitGTK 4.1 no Linux. O launcher cria a sessão ao abrir um item online e a encerra ao retornar à biblioteca. Use HTTPS no Android. O botão de compatibilidade verifica WebAssembly, WebGL, WebGL 2, Canvas 2D, Web Audio e recursos opcionais na página atual. A disponibilidade depende da versão do motor, do suporte gráfico do dispositivo e das políticas da página.

| Plataforma | Itens que o launcher abre | Distribuição |
| --- | --- | --- |
| Windows x64 | Executáveis, atalhos `.lnk` e links HTTP(S) | Instalador Inno Setup por usuário |
| Linux x64 | Executáveis, entradas `.desktop` via GIO e links HTTP(S) | Pacote Debian/Ubuntu |
| Android | Apps instalados com atividade de launcher e links HTTP(S) | APK universal assinado |

## Compilar e testar

Use Flutter 3.50.1 e Python 3. No Windows, instale o workload de desenvolvimento de desktop com C++. No Linux, use Clang, CMake, Ninja, pkg-config e os headers GTK 3. No Android, use Android SDK e JDK 21. Os comandos de preparação geram os runners nativos a partir do Flutter e aplicam as integrações em `packaging/`. Execute a preparação para cada plataforma na máquina que vai compilá-la.

```sh
python packaging/prepare.py windows
flutter pub get
flutter run -d windows
flutter build windows --release
```

No Windows, execute `./packaging/windows.ps1 -Portable` para gerar o ZIP ou execute `./packaging/windows.ps1` com Inno Setup 6 instalado para gerar o instalador. O script inclui as DLLs redistribuíveis do Visual C++ junto ao executável.

No Linux, instale também `libwebkit2gtk-4.1-dev`, gere o runner com `python3 packaging/prepare.py linux`, compile com `flutter build linux --release` e execute `bash packaging/linux.sh 1.3.0` para obter o DEB. No Windows, o navegador precisa do WebView2 Evergreen Runtime. No Android, execute `python packaging/prepare.py android` e `flutter build apk --release` com o SDK da API 36. Sem a chave de produção, a compilação Android usa a assinatura de debug para testes locais.

```sh
flutter gen-l10n
flutter analyze lib test integration_test
flutter test
dart run test/filter_benchmark.dart
```

Para testar o motor embutido no Windows, execute `flutter test -d windows integration_test/browser_test.dart`. O teste abre uma página local e verifica o resultado do diagnóstico WebAssembly.

O microbenchmark compara a normalização de texto em cada pesquisa com a normalização prévia de cada item. Usa 10.000 entradas, cinco consultas, aquecimento e a mediana de 11 amostras de 90 pesquisas. Mede somente o filtro em memória.

Na validação da versão 1.0.0 em Windows x64, o microbenchmark compilado com `dart compile exe` passou de 122,49 ms para 53,19 ms por 90 consultas, redução de cerca de 57%. Em cinco execuções do ZIP portátil, a mediana foi de 323 ms até a fila de entrada da janela ficar ociosa e de 74,8 MiB de memória residente após 1,5 segundo. O instalador dessa versão tinha 10,7 MB.

## GitHub Releases

1. Hospede o código em um repositório público no GitHub. Configure os secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD` e `ANDROID_KEY_ALIAS`. Use a mesma chave Android nas versões distribuídas.
2. Atualize `version` no `pubspec.yaml`, incluindo o número após `+`, que deve aumentar em cada versão Android. Envie uma tag igual à versão sem o número de build, por exemplo `v1.1.0` para `1.1.0+2`.
3. O workflow compila as três plataformas e publica a release após todos os jobs passarem. Ele embute o repositório e a versão no binário. Para builds locais, acrescente `--dart-define=BIGEVIL_REPOSITORY=proprietario/repositorio` e `--dart-define=BIGEVIL_VERSION=1.3.0`, ou informe o repositório na engrenagem do launcher.

O launcher consulta a release estável do repositório ao iniciar e a cada seis horas enquanto estiver aberto. Baixa automaticamente o pacote da sua plataforma quando encontra uma versão mais recente e verifica o tamanho e o SHA-256 informado pelo GitHub. O botão **Instalar** abre o instalador do sistema. No Android, o sistema pode pedir que você autorize esta fonte. No Linux, abra o DEB com o gerenciador de pacotes da distribuição. Se a máquina não tiver um gerenciador gráfico associado a DEB, a mensagem apresenta o caminho do pacote para instalar com `sudo apt install /caminho/BigEvil-Launcher-linux-x64.deb`.

A atualização preserva a biblioteca, que fica no diretório de dados do usuário. O aplicativo mantém os dados localmente e o fluxo de atualização consulta o GitHub.
