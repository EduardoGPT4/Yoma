# Icono y logotipo de YomaShi

## Recursos

- [Icono maestro](../../assets/brand/app_icon.png): PNG de 1024 × 1024, obtenido de la ilustración facilitada por el usuario. La imagen original mide 1199 × 1312; se conserva el cuadrado superior de 1199 × 1199 y se reduce sin estirar el dibujo.
- [Logotipo tipográfico](../../assets/brand/yomashi_wordmark.png): PNG transparente de 1024 × 207. Se normalizó únicamente el tamaño y el margen transparente del resultado generado.

El icono se genera en las cinco densidades de Android. Android 8 y posteriores usan las capas adaptativas con fondo blanco y un margen del 16 % para el primer plano. La configuración está en `pubspec.yaml`, y los recursos compilables en `android/app/src/main/res/`.

El icono maestro no se duplica como recurso Flutter dentro del APK: se incluyen sus versiones nativas. El logotipo sí forma parte del paquete de recursos Flutter.

El logotipo sustituye el título de Inicio. Se muestra dentro de un área táctil de hasta 144 × 48, conserva sus proporciones y usa el color de texto principal del tema claro u oscuro. Su etiqueta accesible sigue siendo «YomaShi», y al tocarlo se abre el resumen de lectura existente.

## Generación del logotipo

Herramienta: **imagegen integrada**, con `transparent_background: true`. La variante seleccionada se generó desde cero; no usa la ilustración del icono como referencia ni necesita claves API en el proyecto.

Prompt final utilizado:

> Create a clean professional typographic wordmark, exact text "YomaShi" with capital Y and S, other letters lowercase. Solid BLACK letters, pure black ink, on a genuinely transparent background with alpha. Minimal bold condensed oblique geometric sans-serif custom lettering, crisp smooth contours, large clearly OPEN counters in the lowercase o and a, excellent legibility at tiny mobile header size. Single line, letters only. Refined kerning. Slightly angular Y and S for a manga reading app, but keep it SIMPLE and FLAT. The image should look like a finished single-color vector wordmark exported as PNG. No textures, no grunge, no speckles, no outlines, no bevel, no extrusion, no white ink, no shadows, no glow, no gradients, no extra words, no symbols, no mascot, no border. Transparent holes inside letters. Wide horizontal composition around 5:1, tightly framed with a little transparent padding.

El color negro del recurso se aplica como una máscara alfa en Flutter, por lo que la misma imagen se muestra clara sobre fondos oscuros y oscura sobre fondos claros.
