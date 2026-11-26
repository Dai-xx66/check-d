// Load a fixed, same-origin PDF.js runtime. Do not send document data to a CDN.
globalThis.checkdPdfReady = (async () => {
  const pdfjs = await import('./vendor/pdfjs-4.6.82/pdf.min.mjs');
  const root = new URL('vendor/pdfjs-4.6.82/', document.baseURI);
  pdfjs.GlobalWorkerOptions.workerSrc = new URL('pdf.worker.min.mjs', root).href;
  // pdfx forwards only cMapUrl/cMapPacked. Add local fonts and disable PDF
  // JavaScript evaluation at this single boundary for all in-memory documents.
  globalThis.pdfjsLib = {
    ...pdfjs,
    getDocument(options) {
      return pdfjs.getDocument({
        ...options,
        isEvalSupported: false,
        standardFontDataUrl: new URL('standard_fonts/', root).href,
      });
    },
  };
  globalThis.pdfRenderOptions = {
    cMapUrl: new URL('cmaps/', root).href,
    cMapPacked: true,
  };
})();
// The Flutter attachment parser awaits this promise and reports a readable
// error if deployment omitted a resource. Other app features can still start.
globalThis.checkdPdfReady.catch(() => {});
