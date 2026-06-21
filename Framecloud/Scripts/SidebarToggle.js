// Clicks Nextcloud's sidebar toggle, if present, to show or hide the sidebar.

(function() {
    var element = document.querySelector('.app-navigation-toggle');
    if (element) {
        element.click();
    }
})();
