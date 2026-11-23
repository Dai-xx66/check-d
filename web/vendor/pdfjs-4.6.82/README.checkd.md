PDF.js 4.6.82 runtime files, pinned to the version documented by pdfx 2.11.0.

Source: https://registry.npmjs.org/pdfjs-dist/-/pdfjs-dist-4.6.82.tgz
Upstream: https://github.com/mozilla/pdf.js
License: Apache-2.0; see LICENSE and the font/CMap notices in their directories.
NPM integrity: sha512-BUOryeRFwvbLe0lOU6NhkJNuVQUp06WxlJVVCsxdmJ4y5cU3O3s3/0DunVdK1PMm7v2MUw52qKYaidhDH1Z9+w==

Only the minified renderer, minified worker, CMaps, standard fonts and their
licenses are included. Examples, viewer UI, source maps and user documents are
excluded. CheckD serves these resources from its own origin, including offline
deployments; PDF bytes are passed to the local worker and are not sent to a CDN.

To upgrade, check pdfx's supported PDF.js version, replace this directory from
the official package, retain licenses, and run the scanned-PDF browser smoke
test. Keep web/pdf_setup.js pointed at the same pinned version.
