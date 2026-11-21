# SDK de entrada para jogos web

Copie `input.mjs` para o projeto do jogo e importe o módulo. Consulte `read()` a cada frame junto com a atualização do jogo.

```js
import { createInput } from './input.mjs';

const input = createInput({ hud: document.querySelector('#hud') });

function frame() {
  const { x, y, pressed } = input.read();
  movePlayer(x, y);
  setPrimaryAction(pressed.has('primary'));
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
```

- `x` e `y` são direções digitais de −1 a 1. `pressed` contém as ações mantidas neste momento.
- As setas ou WASD movem, Espaço/Z acionam `primary`, X aciona `secondary`, e Enter aciona `start`. Passe `keys` para usar outro mapa de códigos físicos. Passe um elemento focável em `surface` para limitar onde o SDK captura teclas.
- No controle com mapeamento padrão, o analógico esquerdo e o direcional movem. Os botões 0, 1 e 9 acionam `primary`, `secondary` e `start`. Use `gamepads` para consultar os eixos e botões brutos de outros joysticks.
- Para controles na tela, coloque elementos como `<button data-action="primary">A</button>` dentro de `hud` e aplique `touch-action: none` ao contêiner. Cada toque é lido separadamente, permitindo pressionar vários botões juntos.
- Ao sair do jogo, chame `input.dispose()` e pare o loop do jogo.

Hospede o jogo por HTTPS e coloque a URL em `onlineUrl` no catálogo do launcher. O módulo também funciona em navegadores externos. Abra `input-test.html` no mesmo servidor para testar entradas ao vivo. Se o joystick não aparecer, pressione um botão com a página em foco e confira se o sistema já reconheceu o dispositivo. A disponibilidade da Gamepad API depende do WebView e do dispositivo.

No Android, o botão Bluetooth do launcher abre a tela de pareamento do sistema. Teclados Bluetooth, USB ou com receptor wireless enviam os mesmos eventos de teclado após a conexão. Jogos nativos devem usar as APIs de entrada do seu próprio motor ou plataforma.
