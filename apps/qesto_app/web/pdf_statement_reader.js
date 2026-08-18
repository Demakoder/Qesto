(function () {
  "use strict";

  const maxPdfSizeBytes = 20 * 1024 * 1024;
  const maxPdfPages = 500;
  const maxExtractedTextCharacters = 5 * 1024 * 1024;
  const scriptUrl = document.currentScript?.src ?? document.baseURI;
  const pdfModuleUrl = new URL("pdfjs/pdf.min.js", scriptUrl).href;
  const pdfWorkerUrl = new URL("pdfjs/pdf.worker.min.js", scriptUrl).href;

  let pdfJsPromise;

  function loadPdfJs() {
    pdfJsPromise ??= import(pdfModuleUrl).then((pdfjs) => {
      pdfjs.GlobalWorkerOptions.workerSrc = pdfWorkerUrl;
      return pdfjs;
    });
    return pdfJsPromise;
  }

  function pickPdfFile() {
    return new Promise((resolve) => {
      const input = document.createElement("input");
      input.type = "file";
      input.accept = ".pdf,application/pdf";
      input.style.display = "none";
      document.body.appendChild(input);

      let settled = false;
      const finish = (file) => {
        if (settled) return;
        settled = true;
        input.remove();
        resolve(file);
      };

      input.addEventListener(
        "change",
        () => finish(input.files?.[0] ?? null),
        { once: true },
      );
      input.addEventListener("cancel", () => finish(null), { once: true });
      window.addEventListener(
        "focus",
        () => setTimeout(() => finish(input.files?.[0] ?? null), 400),
        { once: true },
      );
      input.click();
    });
  }

  function textContentToLines(items) {
    const positioned = items
      .filter(
        (item) =>
          typeof item.str === "string" &&
          item.str.trim().length > 0 &&
          Array.isArray(item.transform),
      )
      .map((item) => ({
        text: item.str.trim(),
        x: item.transform[4],
        y: item.transform[5],
      }))
      .sort((left, right) => {
        const verticalDistance = right.y - left.y;
        return Math.abs(verticalDistance) > 2
          ? verticalDistance
          : left.x - right.x;
      });

    const rows = [];
    for (const item of positioned) {
      const row = rows.at(-1);
      if (!row || Math.abs(row.y - item.y) > 2) {
        rows.push({ y: item.y, items: [item] });
      } else {
        row.items.push(item);
      }
    }

    return rows
      .map((row) =>
        row.items
          .sort((left, right) => left.x - right.x)
          .map((item) => item.text)
          .join(" ")
          .replace(/\s+/g, " ")
          .trim(),
      )
      .filter(Boolean)
      .join("\n");
  }

  async function extractPdfText(file) {
    if (file.size > maxPdfSizeBytes) {
      throw new Error("Размер PDF не должен превышать 20 МБ");
    }
    if (
      file.type !== "application/pdf" &&
      !file.name.toLowerCase().endsWith(".pdf")
    ) {
      throw new Error("Выберите файл в формате PDF");
    }

    const pdfjs = await loadPdfJs();
    const loadingTask = pdfjs.getDocument({
      data: new Uint8Array(await file.arrayBuffer()),
    });
    const document = await loadingTask.promise;

    try {
      if (document.numPages > maxPdfPages) {
        throw new Error("PDF содержит слишком много страниц");
      }
      const pages = [];
      let extractedCharacters = 0;
      for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber++) {
        const page = await document.getPage(pageNumber);
        const content = await page.getTextContent();
        const text = textContentToLines(content.items);
        extractedCharacters += text.length;
        if (extractedCharacters > maxExtractedTextCharacters) {
          throw new Error("Из PDF извлечено слишком много текста");
        }
        pages.push(text);
        page.cleanup();
      }
      return pages.join("\n\f\n");
    } finally {
      await loadingTask.destroy();
    }
  }

  globalThis.qestoPickAndExtractPdf = async function () {
    try {
      const file = await pickPdfFile();
      if (!file) return null;

      const text = await extractPdfText(file);
      return JSON.stringify({ fileName: file.name, text });
    } catch (error) {
      console.error("Qesto PDF import failed", error);
      throw error;
    }
  };
})();
