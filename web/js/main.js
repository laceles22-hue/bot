(() => {
  const header = document.getElementById('site-header');
  const toggle = document.getElementById('nav-toggle');
  const nav = document.getElementById('main-nav');

  toggle.addEventListener('click', () => {
    const open = nav.classList.toggle('open');
    toggle.setAttribute('aria-expanded', String(open));
    toggle.classList.toggle('is-open', open);
  });

  nav.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => {
      nav.classList.remove('open');
      toggle.setAttribute('aria-expanded', 'false');
    });
  });

  window.addEventListener('scroll', () => {
    header.style.boxShadow = window.scrollY > 8 ? '0 1px 0 rgba(26,23,18,0.06)' : 'none';
  });

  const revealTargets = document.querySelectorAll('.reveal');
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.15 });
  revealTargets.forEach((el) => observer.observe(el));

  const yearEl = document.getElementById('year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();
})();
