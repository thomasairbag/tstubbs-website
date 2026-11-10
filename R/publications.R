# R/publications.R
#
# Helpers the pages call to list publications. They read
# data/publications.json, which R/refresh-publications.R writes from Zotero,
# and print HTML. Nothing about a publication is typed here: each entry is
# Zotero's APA citation, with the title linked to the DOI or address, buttons
# for the PDF, DOI or link, and replication data, and any Award and "Cited in"
# lines from the item's Extra field (plan Sections 5 and 6).
#
# In a page (pages run from the project folder; execute-dir in _quarto.yml):
#
#   ```{r}
#   #| echo: false
#   #| output: asis
#   source("R/publications.R")
#   pub_list(c("articles", "commentaries", "chapters", "working-papers"))
#   ```
#
# Functions
#   pub_list(sections, by_year = TRUE, root = "../")  entries under year headings
#   pub_latest(n = 3, root = "")                       the n newest, for Home
#   pub_keys(keys, root = "../")                       chosen items, for About
#   pub_count(sections)                                how many items
# `root` is the path from the page to the site's top folder ("../" for a page
# one folder down, such as /publications/; "" for Home), so the PDF links work
# at the staging address and at tstubbs.net alike.

suppressPackageStartupMessages(library(jsonlite))

pub_data <- fromJSON("data/publications.json", simplifyVector = FALSE)$items

# How many "Cited in" lines show before the rest fold away under "more".
cited_shown <- 3

esc <- function(x) htmltools::htmlEscape(x)

# Prints HTML as a raw block, so Pandoc passes it through untouched (it would
# otherwise read Markdown inside it, turning the underscores in some
# addresses into italics).
emit <- function(html) cat("\n```{=html}\n", paste(html, collapse = "\n"), "\n```\n\n", sep = "")

# Zotero writes characters such as en dashes and curly quotes as numeric
# entities (&#x2013;); turn those into the characters, keeping &amp;.
decode_numeric <- function(s) {
  m <- gregexpr("&#x([0-9A-Fa-f]+);", s)
  regmatches(s, m) <- lapply(regmatches(s, m), function(e) {
    vapply(e, function(x) intToUtf8(strtoi(sub("&#x(.*);", "\\1", x), 16L)), "")
  })
  s
}

# A pattern that finds the title in the citation even where Zotero and the
# title differ in quote marks or dashes, or the citation writes & as &amp;.
title_pattern <- function(title) {
  chars <- strsplit(title, "")[[1]]
  paste(vapply(chars, function(ch) {
    if (ch %in% c("'", "\u2019", "\u2018")) return("['\u2019\u2018]")
    if (ch %in% c('"', "\u201c", "\u201d")) return("[\"\u201c\u201d]")
    if (ch %in% c("-", "\u2013", "\u2014")) return("[-\u2013\u2014]")
    if (ch == "&") return("&amp;")
    if (grepl("[][(){}.*+?^$|\\\\]", ch)) return(paste0("\\", ch))
    ch
  }, ""), collapse = "")
}

pub_link <- function(x) {
  if (!is.null(x$doi)) paste0("https://doi.org/", x$doi) else x$url
}

# Zotero's citation, without its trailing address, with the title linked.
pub_citation <- function(x) {
  cit <- decode_numeric(trimws(x$citation))
  cit <- sub("\\s*https?://\\S+\\s*$", "", cit)
  href <- pub_link(x)
  if (!is.null(href)) {
    m <- regexpr(title_pattern(x$title), cit, perl = TRUE)
    if (m > 0) {
      found <- regmatches(cit, m)
      regmatches(cit, m) <- paste0('<a href="', esc(href), '">', found, "</a>")
    }
  }
  cit
}

btn <- function(href, icon, label) {
  paste0('<a class="pub-btn" href="', esc(href), '"><i class="bi bi-', icon,
         '" aria-hidden="true"></i> ', label, "</a>")
}

pub_buttons <- function(x, root) {
  b <- character()
  if (!is.null(x$pdf)) b <- c(b, btn(paste0(root, x$pdf), "file-earmark-pdf", "PDF"))
  if (!is.null(x$doi)) {
    b <- c(b, btn(paste0("https://doi.org/", x$doi), "link-45deg", "DOI"))
  } else if (!is.null(x$url)) {
    b <- c(b, btn(x$url, "box-arrow-up-right", "Link"))
  }
  if (!is.null(x$data)) b <- c(b, btn(x$data, "database", "Replication data"))
  if (length(b)) paste0('<div class="pub-buttons">', paste(b, collapse = ""), "</div>") else ""
}

# "International Monetary Fund (2025). Title (DP 2025/005)": the body and year
# stay plain, the rest links to the document.
cited_item <- function(ci) {
  m <- regmatches(ci$text, regexec("^(.*?\\(\\d{4}\\)\\.\\s)(.*)$", ci$text))[[1]]
  head <- if (length(m) == 3) m[2] else ""
  rest <- if (length(m) == 3) m[3] else ci$text
  rest_html <- if (!is.null(ci$url)) paste0('<a href="', esc(ci$url), '">', esc(rest), "</a>") else esc(rest)
  paste0("<li>", esc(head), rest_html, "</li>")
}

cited_year <- function(ci) {
  y <- regmatches(ci$text, regexpr("\\((\\d{4})\\)", ci$text))
  if (length(y)) as.integer(gsub("\\D", "", y)) else 0L
}

pub_notes <- function(x) {
  out <- character()
  for (a in unlist(x$awards)) {
    out <- c(out, paste0('<p class="pub-note"><span class="pub-note-label"><i class="bi bi-award" aria-hidden="true"></i> Award</span> ',
                         esc(a), "</p>"))
  }
  ci <- x$cited_in
  if (length(ci)) {
    ci <- ci[order(-vapply(ci, cited_year, 0L))]   # newest first
    items <- vapply(ci, cited_item, "")
    # Fold only when it hides two or more; one more line is simply shown.
    n_show <- if (length(items) <= cited_shown + 1) length(items) else cited_shown
    shown <- head(items, n_show)
    more <- items[-seq_len(n_show)]
    html <- paste0('<div class="pub-cited"><p class="pub-note-label">Cited in</p><ul>',
                   paste(shown, collapse = ""), "</ul>")
    if (length(more)) {
      html <- paste0(html, "<details><summary>", length(more), " more policy document",
                     if (length(more) > 1) "s", "</summary><ul>",
                     paste(more, collapse = ""), "</ul></details>")
    }
    out <- c(out, paste0(html, "</div>"))
  }
  paste(out, collapse = "")
}

pub_entry <- function(x, root = "../", notes = TRUE) {
  paste0('<article class="pub-entry"><p class="pub-cite">', pub_citation(x), "</p>",
         pub_buttons(x, root), if (notes) pub_notes(x), "</article>")
}

pub_items <- function(sections) Filter(function(x) x$section %in% sections, pub_data)

pub_count <- function(sections) length(pub_items(sections))

pub_list <- function(sections, by_year = TRUE, root = "../") {
  items <- pub_items(sections)       # already newest first
  if (!by_year) {
    emit(vapply(items, pub_entry, "", root = root))
    return(invisible())
  }
  years <- unique(vapply(items, function(x) x$year, ""))
  emit(vapply(years, function(y) {
    in_year <- Filter(function(x) identical(x$year, y), items)
    paste0('<section class="pub-year" aria-labelledby="y', y, '"><h2 class="pub-year-heading" id="y', y, '">', y, "</h2>",
           '<div class="pub-year-entries">', paste(vapply(in_year, pub_entry, "", root = root), collapse = ""),
           "</div></section>")
  }, ""))
  invisible()
}

pub_latest <- function(n = 3, root = "") {
  items <- Filter(function(x) x$section != "media", pub_data)
  emit(vapply(head(items, n), pub_entry, "", root = root, notes = FALSE))
  invisible()
}

pub_keys <- function(keys, root = "../") {
  by_key <- setNames(pub_data, vapply(pub_data, function(x) x$key, ""))
  missing <- setdiff(keys, names(by_key))
  if (length(missing)) stop("Not in data/publications.json: ", paste(missing, collapse = ", "))
  emit(vapply(by_key[keys], pub_entry, "", root = root, notes = FALSE))
  invisible()
}
