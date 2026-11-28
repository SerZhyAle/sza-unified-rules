# 4PDA product threads - creation and update procedure

Reference for the [promote](../SKILL.md) skill. Covers creating and updating official product threads on
`4pda.to/forum` under the owner's signed-in account (`SZA`), in Russian, with compact real screenshots and
section-compliant templates.

Third-party forum rules change without notice. Rules below were researched on 2026-11-28; re-read the pinned
rules topic of the target section in the live browser before every create or update pass and record the new
date in the product ticket.

Executor tags follow [PROMOTION.md](../../../rules/PROMOTION.md) §1 rule 9: **A** the agent alone, **A·GO** the
agent after the owner's explicit go naming the product(s) and action, **A→O** the agent up to a human boundary
(sign-in, CAPTCHA, 2FA, moderation consent), **O** the owner alone.

---

## 1. Forum rules and section mapping

### Global rules that bind every pass

- **Rule 1.8 (no unagreed commercial/advertising spam):** pure advertising, paid promotion, referral links,
  monetized wrappers or promotional spam are forbidden without Administration approval. An author's own
  informative, discussion-oriented thread for a free / open-source application following the section template is
  allowed; active author presence also prohibits third-party mods without author consent.
- **Rule 2.1.3 (single account):** one account only (`SZA`). Never register a second account.
- **Rules 3.1-3.2 (language):** natural, readable Russian prose. Raw machine translation from store listings is
  rejected by moderators.
- **Anti-warez:** only legal freeware, open-source builds and official links. Never link or attach cracked
  software or third-party repacks.
- **No duplicates:** before creating a thread, search `4pda.to/forum` by **product name** and (for Android) by
  **package name** (`applicationId`, e.g. `com.sza.fastmediasorter`). If a thread already exists, switch the
  action to `UPDATE`.
- **Canon truth & no competitors ([PROMOTION.md](../../../rules/PROMOTION.md) §1 rule 4):** every stated feature
  must be shipped today (no "planned" or "in development" claims), every version number read from the release
  manifest/tag, and zero competitor product names anywhere in the post.

### Section mapping by product platform

| Platform | Target 4PDA section | Creation flow | Header media & template |
| --- | --- | --- | --- |
| **Android** (phone / tablet / TV / Wear OS companion) | Root of **«Android - Программы»** (curators move into subsections after review) | Always use **«Мастер тем»** (topic wizard); never improvise BBCode headers or decorative Unicode | Square icon **120-200 px** (the only image outside spoiler); real screenshots inside `[spoiler=Скриншоты]`; strictly 1-sentence short description; required `Требуется Android`, `Русский интерфейс`, `Разработчик`, `Домашняя страница`, `Google Play` (or `Нет`), `Имя пакета`, `[spoiler=Скачать:]` with working APK |
| **Windows PC** (desktop utilities & apps) | **«Компьютеры и периферия» -> «Софт»** (or **«Софт от форумчан (Ваши программы)»**) | Standard topic form following pinned **«Оформление шапок тем по программам для ПК»** | Header logo or main UI shot at **320x240 px**; additional real screenshots inside `[spoiler=Скриншоты]`; capabilities in `[LIST][*]..[/LIST]`; supported Windows versions, languages, license, `[url]` official site & GitHub/winget/Store download links |

Note on `Программы -> Для ПК` under `Безопасность в сети`: that subsection holds VPN clients only and is
**not** the Windows desktop software section (observed 2026-11-15 in `CANONR-0023`).

---

## 2. Media rules (icons and compact screenshots)

- **Android icon:** square PNG/JPG, **120-200 px** (target **180x180 px** from the product's 512 px store icon).
  Never exceed 200 px on the longer side.
- **Windows header image:** **320x240 px** (or matching aspect within 320x240 bounds).
- **Screenshots:**
  - Must be **real screenshots of the Russian UI** (no marketing promo renders, no device mockups with ad
    banners, no watermarks, no animated GIFs in Android header screenshots).
  - Resize to compact dimensions before uploading: **max 480 px wide** (or **max 800 px high**) for portrait
    phone screens and **max 800 px wide** for Windows desktop screens, targeting <= 250 KB per image (forum hard
    attachment cap is 200 MB; compact files keep the thread fast and clean).
  - Always place all screenshots inside `[spoiler=Скриншоты]...[/spoiler]`.
  - In Android **«Мастер тем»**, place up to 3 primary screenshots in the main field and any extras in the
    additional screenshots field.

### Compact asset preparation snippet (PowerShell, built-in `System.Drawing`)

Run in a local scratch folder (`temp/<ticket>/4pda-assets/<product>/`), never committing resized copies to
product repos:

```powershell
Add-Type -AssemblyName System.Drawing
function Resize-For4Pda {
    param([string]$Src, [string]$Dst, [int]$MaxW, [int]$MaxH)
    $img = [System.Drawing.Image]::FromFile((Resolve-Path $Src))
    try {
        $ratio = [Math]::Min([Math]::Min($MaxW / $img.Width, $MaxH / $img.Height), 1.0)
        $w = [int][Math]::Round($img.Width * $ratio)
        $h = [int][Math]::Round($img.Height * $ratio)
        $bmp = [System.Drawing.Bitmap]::new($w, $h)
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($img, 0, 0, $w, $h)
            $g.Dispose()
            $null = New-Item -ItemType Directory -Force -Path (Split-Path $Dst)
            $bmp.Save($Dst, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $bmp.Dispose() }
    } finally { $img.Dispose() }
}
# Example:
# Resize-For4Pda -Src 'docs/play/icon-512.png' -Dst 'temp/4pda/icon-180.png' -MaxW 180 -MaxH 180
# Resize-For4Pda -Src 'docs/play/screenshots/phone/ru-RU/1-main.png' -Dst 'temp/4pda/shot-1.png' -MaxW 480 -MaxH 854
```

---

## 3. BBCode templates

### 3.1 Android (`Android - Программы`, via Мастер тем)

Fill the corresponding fields in **Мастер тем** (do not inject custom colors, emojis or Unicode decorations into
the title):

- **Название темы:** exact manifest name (optional English name in parentheses), e.g. `Fast Media Sorter` or
  `Filler: Fill Storage Space` - never `Full`, `RUS`, `Free`, `Лучший`.
- **Краткое описание:** strictly **one sentence** in Russian.
- **Описание:** natural Russian description of shipped capabilities, permissions explanation (if any), and
  supported form factors (phone, tablet, TV, Wear OS).
- **Обязательные поля:**
  - `Требуется Android:` e.g. `8.0 и выше`
  - `Русский интерфейс:` `Да`
  - `Разработчик:` `Serhii Zhyhunenko (SerZhyAle)`
  - `Домашняя страница:` official GitHub Pages product site (and/or GitHub repository)
  - `Google Play:` live Play Store URL (or `Нет`, with direct GitHub Releases source)
  - `Имя пакета:` exact `applicationId` (e.g. `com.sza.fastmediasorter`)
- **Иконка:** 180x180 px square PNG.
- **Скриншоты:** 3-5 compact real Russian screenshots under `[spoiler=Скриншоты]`.
- **Скачать:** `[spoiler=Скачать:]` with `[B]Версия: <versionName>[/B]` and the signed release APK attachment
  (plus Wear OS APK if shipped) and official GitHub Releases / Google Play links.

### 3.2 Windows PC (`Компьютеры и периферия -> Софт`)

```bbcode
[size=4][b]<Product Name>[/b][/size]
[b]Версия:[/b] <version> | [b]Обновлено:[/b] <DD.MM.YYYY>

<Attached 320x240 header image>

[b]Краткое описание:[/b]
<1-2 natural Russian sentences explaining what the program solves.>

[b]Основные возможности:[/b]
[list]
[*] <Capability 1 - shipped, truthful>
[*] <Capability 2>
[/list]

[spoiler=Скриншоты]
<Attached compact real Russian screenshots>
[/spoiler]

[b]Поддерживаемые ОС:[/b] Windows 10 / 11 (x64)
[b]Язык интерфейса:[/b] Русский, Английский, Украинский (и др. по факту)
[b]Лицензия:[/b] Бесплатно, открытый исходный код (<MIT / Apache 2.0>)
[b]Официальный сайт:[/b] [url=<site-url>]<site-url>[/url]
[b]Исходный код и релизы:[/b] [url=<github-url>]GitHub[/url]

[spoiler=Скачать]
[b]Версия <version>:[/b]
[list]
[*] [url=<github-release-url>]GitHub Releases (установщик / portable ZIP + SHA256)[/url]
[*] winget: [code]winget install <PackageIdentifier>[/code]
[*] Microsoft Store: <Store URL if live>
[/list]
[/spoiler]
```

---

## 4. Execution order (create and update)

| # | Step | Tag | What it does |
| --- | --- | --- | --- |
| 0 | Eligibility & asset prep | **A** | Confirm a public release exists (no unreleased / preview-only apps unless owner explicitly orders preview). Read exact version, `minSdk` / OS, links and Russian prose from the product repo. Draft the post text, resize icon and real Russian screenshots into `temp/<ticket>/4pda-assets/<product>/`, verify dimensions and byte sizes. |
| 1 | Signed-in browser session | **A→O** | Owner signs into `https://4pda.to/forum` in Chrome (account `SZA`) and enables the Chrome extension or Chrome remote debugging (`127.0.0.1:9222`, clicking Allow). Agent opens a tab, verifies the signed-in handle is `SZA`, and never reads or stores cookies or passwords. |
| 2 | Live rules & duplicate check | **A** | Open the pinned rules topic of the target section (`Android - Программы` or `Компьютеры и периферия -> Софт`) and record the read date. Search `4pda.to/forum` by product name and Android package name. Classify each product as `CREATE` (no thread exists) or `UPDATE` (owner's thread exists). If another user already maintains a thread, stop and ask the owner before acting. |
| 3 | Create or update thread | **A·GO** | Quote the owner's go naming the product(s) in the go ledger first. **Create:** fill Мастер тем (Android) or new-topic form (Windows), attach icon, compact screenshots and release APK (when approved), preview rendered BBCode, submit once. **Update:** edit the first post (version, update date, move prior version to `[spoiler=Прошлые версии]`, attach/link new release, refresh changed features/screenshots), save, then post one concise Russian changelog reply (`Обновлено до версии <v>: ...`). Stagger across products per `PROMOTION.md` §1 rule 7. |
| 4 | Verify & record | **A** | Open the live topic URL, confirm HTTP 200, author handle `SZA`, clean rendering of icon, `[spoiler=Скриншоты]` and `[spoiler=Скачать:]`, and working links/attachments. Record URL, section, version and date in the 4PDA thread ledger and the product's promotion ticket. |

---

## 5. Stops

Stop immediately and hand the exact step back to the owner on any of:

- A sign-in form, password prompt, CAPTCHA, e-mail/SMS verification code, or Chrome remote-debugging Allow
  prompt when no human is present (headless queue passes never attempt live 4PDA browser steps).
- A moderator warning, pre-moderation hold notice, or live section rule stating that the product category
  requires Administration agreement under rule 1.8.
- An existing thread created by another forum member for the same product (curator transfer / official
  developer status is an owner decision).
- Any control that deletes a topic, deletes an attachment irreversibly, or modifies account settings.
- Two to three failed form or upload attempts (`PROMOTION.md` §1 rule 9).

---

## 6. Release update cadence

- Update a product's 4PDA thread **only when a new public release ships** (`PROMOTION.md` §1 rule 7); never
  bump a thread without a real version update.
- Keep one live thread per product (never create a second thread for a new version).
- Human replies to user questions, bug discussions and moderator dialogue remain **O** (owner voice), with the
  agent drafting suggested factual answers locally on request.
