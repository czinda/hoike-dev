// Inject a "hoike.dev" link at the top of the mdBook sidebar
(function() {
  var sidebar = document.querySelector('.sidebar-scrollbox');
  if (sidebar) {
    var link = document.createElement('a');
    link.href = '/';
    link.className = 'hoike-home-link';
    link.textContent = 'hoike.dev';
    sidebar.insertBefore(link, sidebar.firstChild);
  }
})();
