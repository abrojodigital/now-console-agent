# NOW — Enviar el archivo de la carrera

*(Instrucciones para la persona que maneja el cronometraje. Esta es la única
página de este repositorio escrita en castellano: la lee una timekeeper, no un
programador.)*

---

## Qué es esto

NOW guarda los videos de las carreras para que las familias los encuentren por
corredor. Para saber **qué video corresponde a qué corredor** necesitamos la hora
exacta en que cada uno largó, y esa hora está en el archivo que genera tu propio
programa de cronometraje (SKI PRO).

Este programita hace una sola cosa: **copia ese archivo y nos lo manda** cada vez
que cambia, mientras la carrera está en curso. Mira si hay algo nuevo cada segundo
y solo envía cuando de verdad lo hay.

## Qué hace, y qué no hace

**Lo que hace:**
- mira **una sola carpeta** (la de los eventos de SKI PRO);
- toma el archivo `Event…scdb` que se grabó más recientemente — durante una
  carrera, ese es el evento que se está cronometrando;
- hace una **copia** y envía la copia a NOW;
- manda también la hora del reloj de esta PC (más abajo se explica para qué).

**Lo que no hace, nunca:**
- **no abre el archivo que SKI PRO está usando.** Trabaja siempre sobre una copia.
  Si SKI PRO está escribiendo en ese momento, espera. No puede trabar ni
  interrumpir el cronometraje;
- no instala nada en la PC;
- no modifica ningún archivo de SKI PRO (lo único que escribe es su propio
  `settings.txt` y su registro, dentro de su misma carpeta);
- no mira ninguna otra carpeta ni envía ningún otro archivo que no sea
  `Event…scdb`.

Para desinstalarlo alcanza con **borrar la carpeta**. No queda nada.

## Instalación (una sola vez)

1. Copiá la carpeta **`now-console-agent`** al **Escritorio**.

2. Windows bloquea los archivos que vienen de afuera. Sobre cada uno de los dos
   archivos (`now-console-agent.ps1` y `start-agent.bat`):
   **clic derecho → Propiedades → marcar “Desbloquear” → Aceptar.**

3. Hacé **doble clic en `start-agent.bat`**. Se abre la ventana del programa.
   Ahí se configura todo, sin tocar ningún archivo:

   - **Consola de esta PC:** elegí la tuya de la lista (aparece con tu nombre y
     hasta cuándo vale el código). **Es lo más importante de la configuración:**
     si elegís la de otra persona, los archivos de tu carrera se guardan a su
     nombre. Si la lista no tiene nada elegido, el programa no te deja iniciar
     hasta que elijas.
   - **Carpeta de eventos:** por defecto dice `C:\SkiPro\SkiPro222\Events`. Si
     tus eventos están en otro lado, apretá **Buscar…** y elegí la carpeta. La
     podés ver en SKI PRO (*Configuración local → Directorios → Directorio de las
     pruebas*). Debajo de la carpeta el programa te dice en verde si encontró
     eventos, o en rojo si esa carpeta no existe.
   - **Revisar cada:** dejalo en **1** segundo. Cuanto más rápido mira, mejor
     podemos calcular la hora de cada corredor.
   - **Empezar a enviar apenas se abre el programa:** viene tildado, para que
     alcance con abrirlo el día de la carrera. Destildalo solo si querés
     revisar todo antes de empezar.

   Apretá **Guardar ajustes**. Queda guardado en `settings.txt` y no hace falta
   volver a configurar nada.

   Mientras el programa está enviando, la configuración se bloquea (no se puede
   cambiar nada a mitad de una carrera). Para cambiar algo, apretá **Detener**,
   cambialo, y volvé a **Iniciar envío**.

## Para usarlo, cada día de carrera

**Doble clic en `start-agent.bat`.** Se abre la ventana y, si dejaste tildado
*Empezar a enviar apenas se abre el programa*, arranca sola. Dejala abierta (o
minimizada) mientras dura la carrera.

La parte de **Estado** te dice todo de un vistazo:

- el punto de color y la palabra de arriba: **verde “En marcha”** = todo bien ·
  **amarillo “Conectando…”** = recién arrancó · **rojo “Sin conexión con NOW”** =
  se cortó internet (ver más abajo) · **gris “Detenido”**;
- **Último envío:** la hora y el evento del último archivo que llegó bien;
- **Carrera:** el nombre de la carrera y cuántos largaron, tal como lo leímos;
- **Reloj de la PC:** si tu PC está en hora (ver la sección de los relojes);
- **Carpeta:** qué está haciendo ahora: *sin cambios* (lo normal entre corredor y
  corredor) · *el archivo cambió, pero eso ya lo teníamos* · *SKI PRO está
  escribiendo en este momento; espero* · *todavía no hay ningún archivo*.

El **Registro** de abajo muestra solo lo que pasa de verdad (cada envío, cada
aviso), así no se llena de líneas repetidas:

```
21:24:59  Event065 enviado (2 archivo(s))
     COPA ANTILLANCA  2026-09-20  manga 1: 14/14 largaron, 14 con tiempo
     El reloj de la PC coincide con el nuestro (menos de 5 s)
```

**“enviado”** = llegó bien.

Todo lo que aparece en el Registro queda guardado también en
**`now-console-agent.log`**, en la misma carpeta, por si hace falta mirarlo después
(el botón **Abrir el registro** lo abre).

**Minimizar no detiene nada.** Si minimizás la ventana, el programa sigue
enviando y se va a un ícono redondo junto al reloj de Windows (a veces escondido
en la flechita ^). El color del ícono es el mismo del estado: verde, amarillo,
rojo o gris. Si se corta internet mientras está escondido, Windows te muestra un
aviso. Con doble clic en el ícono, o clic derecho → *Abrir la ventana*, vuelve.

**Para detenerlo:** apretá **Detener**. Si cerrás la ventana con la X mientras
está enviando, el programa te pregunta primero si de verdad querés detenerlo
(para que no se corte el envío de una carrera por accidente). Se puede detener y
volver a arrancar cuando quieras; no se pierde nada.

Solo puede haber **un** programa abierto por PC. Si abrís `start-agent.bat` con
uno ya funcionando, te avisa en vez de abrir otro.

## ⚠️ Los relojes — lo más importante

Acá hay **dos relojes distintos**, y conviene tenerlo claro:

- el **reloj del equipo de cronometraje**, que es el que queda grabado en cada
  impulso del archivo;
- el **reloj de esta PC**, que es el de Windows.

No son el mismo, y cualquiera de los dos puede estar corrido. En una carrera de
septiembre el reloj de un cronómetro estaba **casi dos minutos atrasado**,
siempre igual, sin que nadie lo notara — y con eso los videos quedan asignados al
corredor equivocado.

Al arrancar, el programa **mide el reloj de esta PC contra la hora real** (consulta
nuestro servidor tres veces y se queda con la medición más limpia) y te lo dice en
la línea **Reloj de la PC** de la ventana. Lo repite cada 10 minutos. Eso no
garantiza que el cronómetro esté en hora, pero es la primera señal, y del resto
nos encargamos nosotros: como recibimos el archivo cada pocos segundos, podemos
deducir la hora real de cada impulso por el momento en que nos llega.

```
AVISO: el reloj de la PC esta 127.1 s ATRASADO respecto del nuestro
```

Esa línea de **Reloj de la PC** se pone en amarillo, y el aviso queda en el
Registro.

**Si ves ese aviso, contanos.** No rompe nada — lo podemos corregir de este lado —
pero lo ideal es poner la PC en hora (clic derecho sobre el reloj de Windows →
*Ajustar fecha y hora* → *Sincronizar ahora*). Y si alguna vez ves que la hora que
muestra el cronómetro no coincide con la hora real, avisanos también: ese es el
reloj que más nos importa.

## Si algo no funciona

La ventana muestra el motivo con una línea en **rojo** (o en **amarillo**, si es
solo un aviso), en el Registro o debajo del campo que está mal. Los casos típicos:

| Lo que dice | Qué significa |
|---|---|
| `Elegí la consola de esta PC` | falta elegir tu consola de la lista; sin eso no se puede iniciar |
| `La carpeta no existe` | la carpeta elegida está mal; apretá **Buscar…** y elegí la que tiene los archivos `Event…scdb` |
| `No hay ninguna consola en settings.txt` | el paquete vino sin códigos de acceso; pedinos uno nuevo |
| `ATENCIÓN: el código de esta consola venció` | el código ya no vale; pedinos uno nuevo |
| `Ya hay un agente abierto en esta PC` | ya está funcionando; buscalo junto al reloj de Windows |
| `no enviado: …` | no hay internet en esa PC, o nuestro servidor no responde |
| `AVISO: sin conexion con NOW` | se cortó la conexión. El programa sigue intentando solo y manda los archivos apenas vuelva; no hace falta tocar nada. Si dura mucho, revisá el internet de la PC |
| `conexion con NOW restablecida` | la conexión volvió y el envío sigue normal (es una buena noticia, no un error) |
| `unknown, expired or revoked token` | el código venció; pedinos uno nuevo |

Mandale a NOW el archivo **`now-console-agent.log`**, que está en la misma
carpeta (con el botón **Abrir el registro** lo ves): ahí queda todo lo que hizo el programa, con fecha y hora. Una foto de la
ventana también sirve, pero el archivo dice mucho más.

## Privacidad

El código de acceso (el *token*) es solo para esta PC, vence solo y lo podemos
anular cuando quieras, sin tocar tu computadora. Solo sirve para enviar archivos
de carrera: no da acceso a ninguna otra cosa de NOW.

**Gracias.** Ese archivo es la mejor información que existe sobre lo que pasó en
la pista, y tenerlo el mismo día es lo que nos permite darle a cada chico su
video.
