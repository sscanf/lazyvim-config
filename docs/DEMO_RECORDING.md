# Grabación del Demo GIF - Remote Debugging

## Pasos para Grabar

### 1. Preparar Terminal
```bash
# Abrir terminal en tamaño adecuado
# Tamaño recomendado: 100 columnas x 30 líneas
# Fuente: 14pt o más para legibilidad
```

### 2. Iniciar Peek
```bash
peek &
```
- Configuración en Peek:
  - Format: GIF
  - Frame rate: 15 FPS
  - Delay: 0 seconds
  - Posicionar área de grabación sobre el terminal

### 3. Secuencia de Demostración

#### Escena 1: Diagnóstico Remoto (15 seg)
```bash
cd ~/zitro/projects/zovideo
nvim manager/zovideo.cpp
```
En nvim:
```vim
:DapRemoteDiagnostic
" Esperar a ver el output completo
:q
```

#### Escena 2: Deploy Automático (20 seg)
```bash
nvim manager/zovideo.cpp
```
En nvim:
```vim
:CMakeDeploy
" Ver mensajes:
"   - Subiendo ejecutable
"   - Subiendo plugins .so
"   - Subiendo directorios de config
:q
```

#### Escena 3: Debugging con Breakpoint en .so (30 seg)
```bash
nvim plugins/x11config_video/x11config_video.cpp
```
En nvim:
```vim
50G                      " Ir a línea 50
:DapToggleBreakpoint     " Poner breakpoint (●)
:DapContinue             " Iniciar debug
" Esperar a que conecte y se pare en el breakpoint
" Mostrar variables y stack
:DapTerminate
:q
```

### 4. Guardar GIF
- Peek guardará automáticamente en `~/Videos/` o te preguntará
- Mover a: `/home/vboxuser/.config/nvim/docs/images/demo.gif`

### 5. Optimizar (Opcional)
```bash
# Si el GIF es muy grande (>5MB), optimizar:
gifsicle -O3 --colors 256 \
  ~/Videos/peek-demo.gif \
  -o ~/.config/nvim/docs/images/demo.gif
```

## Estructura del Demo Final

```
0:00 - 0:15  → Diagnóstico remoto (:DapRemoteDiagnostic)
0:15 - 0:35  → Deploy automático (:CMakeDeploy)
0:35 - 1:05  → Debugging + breakpoint en .so
Total: ~65 segundos
```

## Tips
- ✓ Tipear despacio y con pausas
- ✓ Esperar a ver los mensajes completos
- ✓ El círculo rojo del breakpoint debe ser visible
- ✓ Mostrar que el breakpoint se activa en la librería .so
- ✗ No grabar más de 90 segundos (GIF muy pesado)
