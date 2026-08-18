# Compilar NWOG/NDOG como .dll para ATAS

ATAS necesita el indicador como `.dll` compilado (no como `.cs` suelto).
Estos son los pasos para compilarlo en tu PC con Visual Studio.

## 1. Instalar Visual Studio Community (gratis)

Descargala de https://visualstudio.microsoft.com/es/vs/community/
Durante la instalación, elegí la carga de trabajo **".NET desktop development"**.

## 2. Abrir este proyecto

- Abrí Visual Studio.
- "Abrir un proyecto o una solución" → seleccioná el archivo `NwogNdogAtas.csproj`
  de esta carpeta.

## 3. Apuntar las referencias a tu instalación de ATAS

Este proyecto necesita las DLL del SDK de ATAS para compilar. Abrí el
`.csproj` (clic derecho sobre el proyecto → "Editar archivo de proyecto")
y corregí las rutas `HintPath` para que apunten a tu carpeta real de
instalación de ATAS (por defecto suele ser
`C:\Program Files\ATAS Platform\`). Ahí adentro buscá, como mínimo:

- `ATAS.Indicators.dll`
- `ATAS.DataFeedsCore.dll`
- `OFT.Rendering.dll`
- `OFT.Attributes.dll`

Si alguno no aparece con ese nombre exacto, revisá la carpeta y usá el
que más se le parezca (los nombres cambian un poco entre versiones de
ATAS). Si no estás seguro de cuáles hacen falta, la forma más rápida es
agregar referencias a **todos** los `.dll` de esa carpeta (clic derecho
en "Referencias" o "Dependencias" del proyecto → "Agregar referencia" →
"Examinar" → seleccionar todos).

## 4. Compilar

- Arriba, poné la configuración en **Release**.
- Menú "Compilar" → "Compilar solución" (o `Ctrl+Shift+B`).
- Si tira errores de compilación, mandámelos tal cual (texto completo del
  error) y te ayudo a resolverlos.

## 5. Instalar el .dll en ATAS

- El archivo generado va a estar en:
  `indicators\atas-build\bin\Release\net48\NwogNdogAtas.dll`
- Copialo a la carpeta donde ATAS busca indicadores personalizados.
  Esa ruta se configura dentro de ATAS (buscá en Configuración/Settings
  algo como "Custom indicators path", "Extensions" o similar). Si nunca
  la tocaste, probá primero:
  `Documentos\ATAS Platform\Indicators\` (o `...\ATAS\Indicators\`).
- Reiniciá ATAS.
- Buscá "NWOG/NDOG (cryptonnnite)" en el menú de indicadores del gráfico.

## Si no tenés ganas de instalar Visual Studio

También se puede compilar por línea de comandos si tenés el
[.NET SDK](https://dotnet.microsoft.com/download) instalado:

```
cd indicators\atas-build
dotnet build -c Release
```

Mismo resultado, sin abrir la interfaz gráfica de Visual Studio.
