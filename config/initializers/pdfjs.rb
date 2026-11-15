# PDF.js (pdfjs-dist from npm, Apache-2.0) draws PDFs in the document viewer
# on phones, which can't show them in a frame. Its files live in
# public/pdfjs/<version>/ undigested, because it loads its decoders and fonts
# by name; the version in the path keeps the year-long cache safe.
# To update: copy build/pdf.min.mjs, build/pdf.worker.min.mjs, LICENSE, iccs/,
# standard_fonts/ and wasm/ (minus quickjs) into a new folder and change this.
Rails.application.config.x.pdfjs_path = "/pdfjs/6.5.438/"
