/* ==========================================================================
   Cirruscope — brand colours page behaviour
   Highlights the entry in the article's table of contents whose heading is
   currently in view. This page is the only one that has a table of contents,
   which is why it is not part of site.js.
   ========================================================================== */
(() => {
  "use strict";

  const links = [].slice.call(document.querySelectorAll(".article__toc a"));
  if (!links.length || !("IntersectionObserver" in window)) return;

  const map = {};
  links.forEach((l) => {
    map[l.getAttribute("href").slice(1)] = l;
  });

  const heads = document.querySelectorAll(".article__main h2[id]");
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting) return;
        links.forEach((l) => {
          l.classList.remove("is-active");
        });
        if (map[e.target.id]) map[e.target.id].classList.add("is-active");
      });
    },
    { rootMargin: "-88px 0px -70% 0px" },
  );

  heads.forEach((h) => {
    observer.observe(h);
  });
})();
