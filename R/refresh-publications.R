# R/refresh-publications.R
#
# Refreshes the site's publication data from Zotero.
#
# What it does
#   1. Reads every item in the "My Publications" list of Zotero user 9618525
#      through the public Zotero web API. No API key is needed, because
#      My Publications is public.
#   2. Asks Zotero for an APA citation of each item, so that no citation is
#      ever typed into the site.
#   3. Places each item in a section of the site by its Zotero item type,
#      overridden by "site:" tags, and reads the "site-" lines in its Extra field.
#   4. Copies the PDF attached to each article, commentary, chapter, report,
#      and working paper, and to Greening the International Monetary Fund,
#      from your Zotero library on this computer into
#      files/publications/<item key>.pdf (decision 7). It never deletes a file.
#      The PDFs need not be shared in My Publications. On a computer without
#      your Zotero data, it keeps the files already there.
#   5. Copies your CV, the PDF you keep in Dropbox, to
#      files/cv/Thomas_Stubbs_CV.pdf whenever the Dropbox copy is newer and
#      different (decision 21). It only reads the Dropbox file. On a computer
#      without it, it keeps the CV already there.
#   6. Writes data/publications.json, which is committed with the site, and
#      reports what changed since the last run and anything in Zotero that
#      needs attention.
#
# How to run it, from the project folder
#   In RStudio: open the project and source this file.
#   In a terminal: Rscript R/refresh-publications.R
#
# Zotero conventions (plan Section 3; decisions 3, 4, 6, 7, and 14)
#   Tags   "site: commentary"       a journal commentary, not a research article
#          "site: working-paper"    a report listed on Publications, not on Policy
#          "site: media"            a public-writing piece, shown on Media
#   Extra  "site-data: <address>"   replication data, shown as a Data button
#          "site-award: <text>"     an award for the work; one line per award
#          "site-cited: <text> <address>"
#                                   a prominent document citing the work, shown
#                                   under "Cited in"; one line each, address last
#   There are no research-theme tags (decision 14) and no featured items.
#
#   Zotero publishes the Extra field of My Publications items but not their
#   tags. It does let anyone ask which items carry a given tag, so the script
#   asks once for each site tag above. A misspelt tag is therefore not found
#   at all: if a section's count looks wrong, check the spelling in Zotero.

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

settings <- list(
  user_id   = "9618525",
  api       = "https://api.zotero.org",
  style     = "apa",
  locale    = "en-US",   # APA's own terms, e.g. "(Eds.)"; en-GB would print "(Eds)"
  json_file = "data/publications.json",
  pdf_dir   = "files/publications",
  # Zotero's data folder: Zotero's default (the Zotero folder in your home
  # folder), unless the ZOTERO_DATA_DIR environment variable names another.
  zotero_dir = Sys.getenv("ZOTERO_DATA_DIR",
                          file.path(Sys.getenv("USERPROFILE", path.expand("~")), "Zotero")),
  # The CV's source: the PDF in your Dropbox CV folder, unless the
  # TSTUBBS_CV_SOURCE environment variable names another file.
  cv_source = Sys.getenv("TSTUBBS_CV_SOURCE",
                         file.path(Sys.getenv("USERPROFILE", path.expand("~")),
                                   "Dropbox (Personal)", "CV", "CV_Academic.pdf")),
  cv_file   = "files/cv/Thomas_Stubbs_CV.pdf"
)

known_site_tags  <- c("commentary", "working-paper", "media")
known_extra_keys <- c("data", "award", "cited")
section_order    <- c("books", "articles", "commentaries", "chapters",
                      "policy-reports", "working-papers", "media", "unplaced")

# Decision 7: these sections, and the open-access books listed by Zotero key,
# get a PDF on the site (copied in step 3); the checks list any that lack one.
pdf_sections   <- c("articles", "commentaries", "chapters", "policy-reports", "working-papers")
pdf_open_books <- c("XQ7NW3ZS")   # Greening the International Monetary Fund

if (!file.exists("R/refresh-publications.R")) {
  stop("Run this from the project folder, the one that holds R/ and data/.")
}

# Small helpers ---------------------------------------------------------------

`%or%` <- function(a, b) if (is.null(a) || length(a) == 0 || identical(a, "")) b else a

# Drops empty entries so that the JSON carries only what Zotero holds.
compact <- function(x) Filter(function(v) !(is.null(v) || length(v) == 0 || identical(v, "")), x)

zotero_request <- function(path, query = list()) {
  request(settings$api) |>
    req_url_path_append("users", settings$user_id, "publications", path) |>
    req_url_query(!!!query) |>
    req_headers(`Zotero-API-Version` = "3") |>
    req_user_agent("tstubbs-website publication refresh") |>
    req_retry(max_tries = 3) |>
    req_timeout(60)
}

# Follows Zotero's paging until every item is read.
fetch_all <- function(path, query) {
  out   <- list()
  start <- 0
  limit <- 100
  repeat {
    resp  <- req_perform(zotero_request(path, c(query, list(start = start, limit = limit))))
    page  <- resp_body_json(resp, simplifyVector = FALSE)
    out   <- c(out, page)
    total <- suppressWarnings(as.integer(resp_header(resp, "Total-Results")))
    start <- start + limit
    if (length(page) == 0 || is.na(total) || start >= total) break
  }
  out
}

# Asks Zotero which items carry a tag; accepts "site: x" and "site:x".
keys_with_tag <- function(tag) {
  unique(unlist(lapply(c(paste0("site: ", tag), paste0("site:", tag)), function(t) {
    resp <- req_perform(zotero_request("items/top", list(format = "keys", tag = t)))
    keys <- strsplit(resp_body_string(resp), "\r?\n")[[1]]
    keys[nzchar(keys)]
  })))
}

section_for <- function(type, site_tags) {
  if ("media" %in% site_tags) return("media")
  switch(type,
    book           = "books",
    journalArticle = if ("commentary" %in% site_tags) "commentaries" else "articles",
    bookSection    = "chapters",
    report         = if ("working-paper" %in% site_tags) "working-papers" else "policy-reports",
    "unplaced")
}

venue_for <- function(d) {
  switch(d$itemType,
    journalArticle   = d$publicationTitle,
    bookSection      = d$bookTitle,
    book             = d$publisher,
    report           = d$institution,
    newspaperArticle = d$publicationTitle,
    magazineArticle  = d$publicationTitle,
    blogPost         = d$blogTitle,
    webpage          = d$websiteTitle,
    NULL)
}

# Reads "site-..." lines from the Extra field; other Extra lines are ignored.
parse_extra <- function(extra) {
  values  <- list()
  unknown <- character()
  if (is.null(extra) || identical(extra, "")) return(list(values = values, unknown = unknown))
  for (line in strsplit(extra, "\r?\n")[[1]]) {
    m <- regmatches(line, regexec("^\\s*site-([A-Za-z-]+)\\s*:\\s*(.*?)\\s*$", line, perl = TRUE))[[1]]
    if (length(m) == 3) {
      key <- tolower(m[2])
      # A key may repeat: one line per award or citing document.
      if (key %in% known_extra_keys) values[[key]] <- c(values[[key]], m[3]) else unknown <- c(unknown, trimws(line))
    }
  }
  list(values = values, unknown = unknown)
}

# "International Monetary Fund (2025). Title (DP 2025/005) https://..." becomes
# list(text = "International Monetary Fund (2025). Title (DP 2025/005)", url = "https://...").
split_cited <- function(s) {
  m <- regmatches(s, regexec("^(.*?)\\s+(https?://\\S+)$", s, perl = TRUE))[[1]]
  if (length(m) == 3) list(text = m[2], url = m[3]) else list(text = s)
}

clean_doi <- function(doi) {
  if (is.null(doi) || identical(doi, "")) return(NULL)
  sub("^(https?://(dx\\.)?doi\\.org/|doi:\\s*)", "", trimws(doi), ignore.case = TRUE)
}

# Keeps the citation itself, without Zotero's wrapper and inline styles.
citation_html <- function(bib) {
  if (is.null(bib)) return(NULL)
  inner <- sub('(?s)^.*?<div class="csl-entry">(.*)</div>\\s*</div>\\s*$', "\\1", bib, perl = TRUE)
  trimws(inner)
}

short_authors <- function(creators) {
  authors <- Filter(function(cr) identical(cr$role, "author"), creators)
  if (!length(authors)) authors <- creators
  fam <- vapply(authors, function(cr) cr$family %or% "", "")
  if (length(fam) > 3) paste0(paste(fam[1:3], collapse = ", "), " et al.") else paste(fam, collapse = ", ")
}

# 1. Fetch ----------------------------------------------------------------------

cat("Reading Zotero My Publications for user ", settings$user_id, " ...\n", sep = "")
raw <- fetch_all("items/top", list(format = "json", include = "data,bib",
                                   style = settings$style, locale = settings$locale))
tagged      <- setNames(lapply(known_site_tags, keys_with_tag), known_site_tags)

previous <- if (file.exists(settings$json_file)) {
  fromJSON(settings$json_file, simplifyVector = FALSE)
} else NULL

if (length(raw) == 0) {
  stop("Zotero returned no items, so ", settings$json_file, " was left as it is. ",
       "Check that My Publications still holds your items, then run this again.")
}

# 2. Clean ----------------------------------------------------------------------

problems <- list(misplaced_tags = character(), unknown_extra = character())

items <- lapply(raw, function(it) {
  d         <- it$data
  site_tags <- sort(names(Filter(function(k) it$key %in% k, tagged)))
  extra     <- parse_extra(d$extra)
  section   <- section_for(d$itemType, site_tags)
  label     <- paste0('"', d$title, '"')

  if ("commentary" %in% site_tags && d$itemType != "journalArticle")
    problems$misplaced_tags <<- c(problems$misplaced_tags, paste0(label, ": 'site: commentary' on a ", d$itemType))
  if ("working-paper" %in% site_tags && d$itemType != "report")
    problems$misplaced_tags <<- c(problems$misplaced_tags, paste0(label, ": 'site: working-paper' on a ", d$itemType))
  if (length(extra$unknown)) problems$unknown_extra <<- c(problems$unknown_extra,
                                                          paste0(label, ": ", extra$unknown))

  creators <- lapply(d$creators, function(cr) compact(list(
    role   = cr$creatorType,
    family = cr$lastName %or% cr$name,
    given  = cr$firstName
  )))

  record <- compact(list(
    key           = it$key,
    version       = d$version,
    type          = d$itemType,
    section       = section,
    year          = substr(it$meta$parsedDate %or% "", 1, 4),
    sort_date     = it$meta$parsedDate,
    date          = d$date,
    title         = d$title,
    creators      = creators,
    venue         = venue_for(d),
    report_type   = d$reportType,
    report_number = d$reportNumber,
    doi           = clean_doi(d$DOI),
    url           = d$url,
    data          = extra$values$data[1],
    awards        = if (length(extra$values$award)) I(extra$values$award),
    cited_in      = if (length(extra$values$cited)) lapply(extra$values$cited, split_cited),
    citation      = citation_html(it$bib)
  ))
  # Always present, even when empty, because the pages place items by them.
  record$site_tags <- I(site_tags)
  record
})

# 3. Files ----------------------------------------------------------------------
# Decision 7, as amended on 6 November 2026: each PDF is copied from the file
# attached to the item in your own Zotero library on this computer; nothing
# needs to be shared in My Publications. Zotero's database is read from a
# temporary copy, so Zotero itself is never touched, open or closed. Which
# items get a PDF is set by pdf_sections and pdf_open_books above.

pdf_wanted <- function(x) x$section %in% pdf_sections || x$key %in% pdf_open_books
pdf_path   <- function(key) file.path(settings$pdf_dir, paste0(key, ".pdf"))
pdf_notes  <- list(several = character(), missing = character())
n_copied   <- 0
db_file    <- file.path(settings$zotero_dir, "zotero.sqlite")

if (!file.exists(db_file)) {
  cat("\nZotero's data folder was not found at ", settings$zotero_dir, ", so the PDFs were not\n",
      "refreshed; the files already in ", settings$pdf_dir, " are kept. If Zotero keeps its\n",
      "data elsewhere, set ZOTERO_DATA_DIR to that folder.\n", sep = "")
} else {
  tmp <- tempfile("zotero-")
  dir.create(tmp)
  file.copy(db_file, file.path(tmp, "zotero.sqlite"))
  wal <- paste0(db_file, "-wal")
  if (file.exists(wal) && file.size(wal) > 0) file.copy(wal, file.path(tmp, "zotero.sqlite-wal"))
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(tmp, "zotero.sqlite"))
  attached <- DBI::dbGetQuery(con, "
    SELECT p.key AS parent, i.key AS attachment, a.path AS path
    FROM itemAttachments a
    JOIN items i     ON i.itemID = a.itemID
    JOIN items p     ON p.itemID = a.parentItemID
    JOIN libraries l ON l.libraryID = i.libraryID
    WHERE l.type = 'user'
      AND a.contentType = 'application/pdf'
      AND a.linkMode IN (0, 1)
      AND a.path LIKE 'storage:%'
      AND a.itemID NOT IN (SELECT itemID FROM deletedItems)
    ORDER BY i.dateAdded, i.key")
  DBI::dbDisconnect(con)
  unlink(tmp, recursive = TRUE)

  dir.create(settings$pdf_dir, recursive = TRUE, showWarnings = FALSE)
  for (x in Filter(pdf_wanted, items)) {
    rows <- attached[attached$parent == x$key, , drop = FALSE]
    if (nrow(rows) == 0) next                         # listed under Checks
    if (nrow(rows) > 1) pdf_notes$several <- c(pdf_notes$several, x$key)
    src <- file.path(settings$zotero_dir, "storage", rows$attachment[1],
                     sub("^storage:", "", rows$path[1]))   # the first PDF attached wins
    if (!file.exists(src)) {
      pdf_notes$missing <- c(pdf_notes$missing, x$key)
      next
    }
    dest <- pdf_path(x$key)
    if (!file.exists(dest) || !identical(unname(tools::md5sum(dest)), unname(tools::md5sum(src)))) {
      file.copy(src, dest, overwrite = TRUE)
      n_copied <- n_copied + 1
    }
  }
}

items <- lapply(items, function(x) {
  if (pdf_wanted(x) && file.exists(pdf_path(x$key))) x$pdf <- pdf_path(x$key)
  x
})
used    <- unlist(lapply(items, function(x) x$pdf))
orphans <- setdiff(list.files(settings$pdf_dir, pattern = "\\.pdf$", full.names = TRUE), used)

# 3b. CV ------------------------------------------------------------------------
# Decision 21 (10 November 2026): the site's CV is the PDF you keep in Dropbox,
# copied whenever the Dropbox copy is newer and different, so the site's CV
# cannot go stale. The copy keeps the Dropbox file's date. The Dropbox file is
# only read; nothing is ever deleted.

cv <- list(status = "", not_pdf = FALSE, site_newer = FALSE, word_newer = FALSE)
cv_date <- function(path) sub("^0", "", format(file.mtime(path), "%d %B %Y, %H:%M"))

if (!file.exists(settings$cv_source)) {
  cv$status <- paste0("kept (", settings$cv_source, " not found on this computer)")
} else if (!identical(readBin(settings$cv_source, "raw", 4), charToRaw("%PDF"))) {
  cv$not_pdf <- TRUE
  cv$status  <- "kept (the Dropbox file is not a PDF)"
} else {
  dir.create(dirname(settings$cv_file), recursive = TRUE, showWarnings = FALSE)
  same <- file.exists(settings$cv_file) &&
    identical(unname(tools::md5sum(settings$cv_file)), unname(tools::md5sum(settings$cv_source)))
  if (same) {
    cv$status <- paste0("unchanged (Dropbox copy saved ", cv_date(settings$cv_source), ")")
  } else if (!file.exists(settings$cv_file) ||
             file.mtime(settings$cv_source) > file.mtime(settings$cv_file)) {
    file.copy(settings$cv_source, settings$cv_file, overwrite = TRUE, copy.date = TRUE)
    cv$status <- paste0("copied from Dropbox (saved ", cv_date(settings$cv_source), ")")
  } else {
    cv$site_newer <- TRUE
    cv$status <- "kept (the site's copy is newer than Dropbox's)"
  }
  # A Word file saved after its PDF usually means the PDF was not saved again.
  cv_docx <- sub("\\.pdf$", ".docx", settings$cv_source, ignore.case = TRUE)
  cv$word_newer <- file.exists(cv_docx) &&
    file.mtime(cv_docx) > file.mtime(settings$cv_source) + 120
}

# 4. Write ----------------------------------------------------------------------

ord   <- order(vapply(items, function(x) x$sort_date %or% "0000", ""),
               vapply(items, function(x) x$title %or% "", ""), decreasing = c(TRUE, FALSE),
               method = "radix")
items <- items[ord]

sections <- vapply(items, function(x) x$section, "")
counts   <- table(factor(sections, levels = section_order))
counts   <- counts[counts > 0]
versions <- vapply(items, function(x) as.numeric(x$version), 0)

out <- list(
  meta = list(
    source         = paste0(settings$api, "/users/", settings$user_id, "/publications/items/top"),
    style          = settings$style,
    locale         = settings$locale,
    count          = length(items),
    sections       = as.list(counts),
    zotero_version = max(versions)
  ),
  items = items
)

json <- toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null")
dir.create(dirname(settings$json_file), recursive = TRUE, showWarnings = FALSE)
old_json <- if (file.exists(settings$json_file)) paste(readLines(settings$json_file, encoding = "UTF-8", warn = FALSE), collapse = "\n") else ""
if (identical(old_json, as.character(json))) {
  cat("\nNo change: ", settings$json_file, " already matches Zotero.\n", sep = "")
} else {
  writeLines(enc2utf8(as.character(json)), settings$json_file, useBytes = TRUE)
  cat("\nWrote ", settings$json_file, "\n", sep = "")
}

# 5. Report ---------------------------------------------------------------------

line_for <- function(x) sprintf("%s  %-15s %-28s %s", x$year %or% "????", x$section,
                                substr(short_authors(x$creators), 1, 28), substr(x$title, 1, 70))

cat("\nZotero My Publications: ", length(items), " items (Zotero version ", max(versions), ")\n", sep = "")
for (s in names(counts)) cat(sprintf("  %-16s %3d\n", s, counts[[s]]))
cat(sprintf("  %-16s %3d", "PDFs on the site", length(used)),
    if (n_copied) sprintf("(%d copied from Zotero this run)", n_copied), "\n")
cat(sprintf("  %-16s %s\n", "CV", cv$status))

cat("\nChanges since the last run\n")
if (is.null(previous)) {
  cat("  First run.\n")
} else {
  prev  <- setNames(previous$items, vapply(previous$items, function(x) x$key, ""))
  now   <- setNames(items, keys <- vapply(items, function(x) x$key, ""))
  added   <- setdiff(names(now), names(prev))
  removed <- setdiff(names(prev), names(now))
  changed <- Filter(function(k) !identical(as.numeric(prev[[k]]$version), as.numeric(now[[k]]$version)),
                    intersect(names(now), names(prev)))
  if (!length(c(added, removed, changed))) cat("  None.\n")
  for (k in added)   cat("  + added    ", line_for(now[[k]]), "\n", sep = "")
  for (k in removed) cat("  - removed  ", line_for(prev[[k]]), "\n", sep = "")
  for (k in changed) cat("  ~ changed  ", line_for(now[[k]]), "\n", sep = "")
}

cat("\nChecks\n")
n_issues <- 0
flag <- function(heading, lines) {
  if (!length(lines)) return(invisible())
  n_issues <<- n_issues + length(lines)
  cat("  ! ", heading, " (", length(lines), ")\n", sep = "")
  for (l in lines) cat("      ", l, "\n", sep = "")
}

no_link <- Filter(function(x) is.null(x$doi) && is.null(x$url) && is.null(x$pdf), items)
flag("No DOI, URL, or PDF, so nothing to click on the site", vapply(no_link, line_for, ""))

no_pdf <- Filter(function(x) is.null(x$pdf) &&
                   (x$section %in% pdf_sections || x$key %in% pdf_open_books), items)
flag("Should have a PDF, but Zotero has no PDF attached to it (decision 7)",
     vapply(no_pdf, line_for, ""))
flag("More than one PDF attached in Zotero; the first attached is used",
     vapply(Filter(function(x) x$key %in% pdf_notes$several, items), line_for, ""))
flag("PDF attached in Zotero but its file is not on this computer (sync Zotero's files)",
     vapply(Filter(function(x) x$key %in% pdf_notes$missing, items), line_for, ""))

dois <- vapply(items, function(x) tolower(x$doi %or% ""), "")
dup  <- setdiff(unique(dois[duplicated(dois)]), "")
flag("The same DOI on more than one item", unlist(lapply(dup, function(d)
  paste0(d, ": ", vapply(items[dois == d], function(x) x$title, ""), collapse = " | "))))

flag("site: tags on the wrong item type", problems$misplaced_tags)
flag("Unknown site- lines in Extra", problems$unknown_extra)
flag("Items with no section (unexpected item type)",
     vapply(Filter(function(x) x$section == "unplaced", items), line_for, ""))

no_url_cited <- unlist(lapply(items, function(x) vapply(x$cited_in %or% list(), function(ci)
  if (is.null(ci$url)) paste0(line_for(x), "  <- ", ci$text) else NA_character_, "")))
flag("site-cited lines without an address at the end", no_url_cited[!is.na(no_url_cited)])
flag(paste0("PDFs in ", settings$pdf_dir, " not used by any item (not deleted)"), orphans)

flag("The CV in Dropbox is not a PDF, so the site's CV was not replaced",
     if (cv$not_pdf) settings$cv_source)
flag("The site's CV is newer than the one in Dropbox, so it was not replaced",
     if (cv$site_newer) paste0(settings$cv_file, " (", cv_date(settings$cv_file), ") vs Dropbox (",
                               cv_date(settings$cv_source), ")"))
flag("The CV's Word file was saved after its PDF: save the PDF again, then run this again",
     if (cv$word_newer) sub("\\.pdf$", ".docx", settings$cv_source, ignore.case = TRUE))

if (n_issues == 0) cat("  Nothing needs attention.\n")
