# KZT to RUB Converter

Millennium Steam Client plugin that shows an approximate RUB price next to KZT prices in the Steam store.

Russian version: `README_RU.md`

## Installation

1. Close Steam.
2. Copy this project folder into `Steam\plugins` or `Steam\millennium\plugins`.
3. Start Steam.
4. Enable the plugin in Millennium.
5. Open the Steam store.

The plugin will automatically copy the required files into `Steam\steamui` and start working without extra setup.

## How the rate is calculated

On startup, the plugin requests the KZT -> RUB exchange rate once and then keeps using it until the next Steam restart.

It checks these providers in order:

1. `cbr-xml-daily.ru`
2. `ratata.money`
3. `api.frankfurter.dev`
4. `open.er-api.com`

If none of them responds, the plugin switches to `Offline converter`.

## What Offline converter means

This is a fallback mode for cases where all rate providers are unavailable, blocked, or too slow to respond.

In this mode, the price is calculated with a simple formula:

```text
RUB = KZT / 6
```

It is not an exact bank exchange rate, but a quick approximate conversion so the plugin can still show RUB prices even without access to online rate services.

## Troubleshooting

If the plugin does not work:

- Make sure this project folder is placed directly inside `Steam\plugins` or `Steam\millennium\plugins`.
- Make sure the plugin is enabled in Millennium.
- Fully restart Steam after installing or updating the plugin.
- If Steam is installed in a protected folder such as `Program Files`, try running Steam with elevated permissions.

If RUB prices do not appear:

- Open the Steam store, not the library.
- Wait 1-2 seconds after the page opens: the plugin first resolves the rate, then adds the conversion.
- If all rate providers are unavailable, the plugin should fall back to `Offline converter`.

If you want to check which rate source was used:

- Open the Millennium logs.
- Look for `Requesting data from ...`
- Look for `Selected exchange rate source: ...`

If Millennium does not show those lines, open `kzt_rub_converter.log` in the plugin folder next to `plugin.json`.

```text
...\plugin_folder\kzt_rub_converter.log
```
