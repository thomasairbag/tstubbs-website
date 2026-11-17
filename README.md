# Thomas Stubbs website

The personal academic and policy website of Thomas Stubbs, Professor of Global Political Economy at Royal Holloway, University of London. This repository holds its source; the site is live at https://tstubbs.net/. Contact: [thomas.stubbs@rhul.ac.uk](mailto:thomas.stubbs@rhul.ac.uk).

## How the site is built

- **Pages:** a Quarto website. Each page is `<slug>/index.qmd` (Home is `index.qmd`): `about`, `books`, `publications` (Academic Writing, which keeps its old address), `policy` (Policy & Advisory), `media`, `teaching`, `cv`, and `contact`, with `404.qmd` for addresses that do not exist. Quarto renders them into `docs/` as plain HTML. GitHub Pages serves `docs/` from the `main` branch, so `docs/` is committed with the sources. Only `.qmd` files are rendered, so this README, `CHANGELOG.md`, and `CLAUDE.md` never appear on the site.
- **Publications:** Zotero is the one place a publication is edited. `R/refresh-publications.R` reads the public "My Publications" list of Zotero user 9618525 through the Zotero web API (no key needed) and writes `data/publications.json`, which is committed, so a render never depends on Zotero. It also copies each item's PDF from the Zotero library on this computer to `files/publications/<item key>.pdf`. Pages print the lists through the helpers in `R/publications.R` (`pub_list`, `pub_latest`, `pub_keys`, `book_header`, `book_cited`, `book_card`), using Zotero's own APA citation, so no citation is typed into a page.
- **Which page an item appears on** follows its Zotero item type, overridden by a tag:

  | Zotero | Section | Page |
  | --- | --- | --- |
  | Journal Article | articles | Academic Writing |
  | Journal Article tagged `site: commentary` | commentaries | Academic Writing |
  | Book Section | chapters | Academic Writing |
  | Report tagged `site: working-paper` | working papers | Academic Writing |
  | Report | policy reports | Policy & Advisory |
  | Book | books | Books (by key; see below) |
  | any type tagged `site: media` | media | Media |

  Home shows the three newest items outside Media. About's selected works are listed by Zotero key in `about/index.qmd`.
- **Extra lines:** in an item's Extra field in Zotero, `site-data: <address>` adds a Data button (replication data), `site-award: <text>` an award line, and `site-cited: <text> <address>` a line under "Cited in" (a policy document citing the work, address last). One line each; a key may repeat. Other Extra lines are ignored.
- **The CV:** one PDF at `files/cv/Thomas_Stubbs_CV.pdf`. The refresh script copies it from the CV PDF in Thomas's Dropbox whenever that copy is newer and different (the path is in the script's settings; the `TSTUBBS_CV_SOURCE` environment variable overrides it).
- **Other facts:** `data/site.yml` holds the name, posts, contact details, profile links, areas of expertise, and the search description, and the pages read them from there. The four organisations named on Home and About are written into those pages' sentences; `data/policy-projects.yml` keeps the same list, but no page reads it, so a change goes in all three. The Books page's covers (`images/`), descriptions, and praise are written in `books/index.qmd`; Zotero supplies each book's title line, buttons, and "Cited in" lines.
- **Design:** `_quarto.yml` holds the menu, the profile icons in the menu bar, the footer, `site-url`, and the Google Analytics ID; `styles/custom.scss` the colours, type, and layout; `styles/fonts.css` and `fonts/` the self-hosted fonts (Fraunces and IBM Plex Sans), with their licences; `_includes/` the page-title template and the skip link. `R/make-favicon.R` draws `images/favicon.png`.
- **Domain:** the `CNAME` file names the domain, tstubbs.net, for GitHub Pages, and `.nojekyll` makes it serve the files as they are. Quarto copies both into `docs/`.
- **Conventions:** `CLAUDE.md` records the project's working rules and decisions in more detail.

## Preview and render

Rendering needs Quarto, which comes with RStudio (the site is built with Quarto 1.9), and R (4.3) with the packages htmltools, jsonlite, knitr, rmarkdown, and yaml. The refresh script also needs httr2, DBI, and RSQLite; `R/make-favicon.R` needs magick.

- **RStudio:** open `tstubbs-website.Rproj`, then Build → Render Website. This renders every page into `docs/` and opens a preview.
- **Terminal**, in the project folder: `quarto render` builds the whole site; `quarto preview` serves it and re-renders each page as you save it.

Stop any preview before a full render. On Windows, a server holding `docs/` open makes the render fail partway, leaving `docs/` incomplete until the next render. After a Quarto upgrade, check `_includes/metadata.html`: it is a copy of Quarto's own template partial, changed only to write page titles as "Academic Writing | Thomas Stubbs". The menu fits on one line from 992px wide; check it again after changing a menu label or icon.

## Maintenance guide: adding a publication

1. **Add it to Zotero** and tick My Publications. Check the item type (it decides the page; see the table above), the date, and the DOI or URL. For an article, commentary, chapter, report, or working paper, attach the PDF in Zotero; it need not be shared in My Publications.
2. **Mark it for the site, if needed:** a `site: commentary`, `site: working-paper`, or `site: media` tag, spelt exactly so; and any `site-data:`, `site-award:`, or `site-cited:` lines in Extra.
3. **Run the refresh script** from the project folder: in RStudio, source `R/refresh-publications.R`; in a terminal, `Rscript R/refresh-publications.R`. It prints the count in each section, what changed since the last run, and anything that needs attention, such as an item with nothing to click on or one that should have a PDF but has none. If a section's count looks wrong, check the tag's spelling in Zotero.
4. **Render** the whole site, and check the new entry in the preview: its citation, its buttons, and that its PDF opens.
5. **Commit and push to `main`**, with `data/publications.json`, the new PDF in `files/publications/`, and `docs/` in one commit. A push publishes the site: GitHub Pages rebuilds it within a minute or two. Then check the entry on https://tstubbs.net/.

A correction (a title, a date, a "Cited in" line) is made in Zotero and follows steps 3 to 5. To take an item off the site, untick My Publications in Zotero; the script never deletes a PDF, so also delete its file from `files/publications/`, then steps 3 to 5. A new book also needs its own section in `books/index.qmd`, with its cover in `images/`, and a card on Home (`book_card` in `index.qmd`); if it is open access, add its Zotero key to `pdf_open_books` in the refresh script.

## Updating the CV

1. Save the new CV as a PDF over the old one in the Dropbox CV folder, after the last change to the Word file. The script warns if the Word file was saved after the PDF.
2. Run the refresh script. Its summary says "copied from Dropbox" with the PDF's date.
3. Render (the CV page's download button gives the file's size, read at render), then commit and push `files/cv/` with `docs/`. The CV keeps its address, https://tstubbs.net/files/cv/Thomas_Stubbs_CV.pdf.

## Other changes

- **Page text:** edit the page's `index.qmd`, render, check, commit, and push.
- **Facts in `data/site.yml`:** a profile link also appears in the menu bar if it has an icon there, so change it in `_quarto.yml` too. The search description is in three places that change together: `data/site.yml`, `_quarto.yml` (`website: description`), and `index.qmd` (`description-meta`).
- **`CHANGELOG.md`:** add a dated entry for a change to the site's pages, design, or set-up. New publications and CV updates need none; the commit history records them.

## Moving to another host

The site needs no server or database: `docs/` is the whole site, as plain files, so any static host can serve it.

The domain is registered at GoDaddy, which also hosts its DNS. The records:

- `@`: GitHub's four A records (185.199.108.153, 185.199.109.153, 185.199.110.153, and 185.199.111.153) and four AAAA records (2606:50c0:8000::153, 2606:50c0:8001::153, 2606:50c0:8002::153, and 2606:50c0:8003::153);
- `www`: a CNAME to `thomasairbag.github.io`, which GitHub redirects to tstubbs.net;
- TXT records verifying the domain with GitHub (`_github-pages-challenge-thomasairbag`) and with Google Search Console (`@`);
- GoDaddy's two MX records at `@` (`smtp.secureserver.net` and `mailstore1.secureserver.net`), and its `email` (webmail) and `_domainconnect` CNAMEs.

A move changes only the A, AAAA, and `www` records; the others stay as they are.

The A, AAAA, and `www` records have a TTL of 600 seconds, so a change takes effect within about 10 minutes.

To move:

1. **Publish `docs/` on the new host**, with tstubbs.net as its custom domain, and test it at the host's own address first. The new host must also do what GitHub Pages does: serve `404.html` for missing addresses (old Owlstown addresses reach it), redirect addresses without a trailing slash (`/cv` to `/cv/`), and provide HTTPS.
2. **Repoint the DNS at GoDaddy:** replace GitHub's A, AAAA, and `www` records with the new host's, and keep the others.
3. **Update the repository:** change `site-url` in `_quarto.yml` and the `CNAME` file if the address changes (only GitHub Pages reads `CNAME` and `.nojekyll`), then render, commit, and push.
4. **Leave GitHub Pages:** once the new host serves the site over HTTPS, remove the custom domain under the repository's Settings → Pages.
5. **Test the live site:** HTTPS, the `www` redirect, the 404 page, and every link and PDF.

To move back, restore GitHub's records above at GoDaddy.
