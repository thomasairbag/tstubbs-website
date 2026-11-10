# R/make-favicon.R
#
# Draws the browser-tab icon, images/favicon.png: "TS" in the page colour on
# an oxblood rounded square, as in the approved Stage 2 mock-ups (decision 19).
# The letters are drawn here, on this computer, so visitors' browsers do not
# need the font. Needs the magick package.
#
# Run from the project folder: Rscript R/make-favicon.R

suppressPackageStartupMessages(library(magick))

svg <- '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="12" fill="#7B2D26"/>
  <text x="32" y="43" text-anchor="middle" font-family="Georgia, serif" font-size="30"
        font-weight="600" fill="#FAF8F3" letter-spacing="-1">TS</text>
</svg>'

icon <- image_read_svg(svg, width = 64, height = 64)
image_write(icon, "images/favicon.png", format = "png")
cat("Wrote images/favicon.png (", file.size("images/favicon.png"), " bytes)\n", sep = "")
