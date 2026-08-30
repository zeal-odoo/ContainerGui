"use strict";

(function exposePagination(scope) {
  function range(start, end) {
    return Array.from({ length: end - start + 1 }, (_, index) => start + index);
  }

  function visiblePages(currentPage, totalPages) {
    if (totalPages <= 10) return range(1, totalPages);
    if (currentPage <= 6) return [...range(1, 9), "ellipsis", totalPages];
    if (currentPage >= totalPages - 5) {
      return [1, "ellipsis", ...range(totalPages - 8, totalPages)];
    }
    return [
      1,
      "ellipsis",
      ...range(currentPage - 3, currentPage + 3),
      "ellipsis",
      totalPages
    ];
  }

  function pageCount(totalCount, pageSize) {
    return Math.min(500, Math.max(1, Math.ceil(totalCount / pageSize)));
  }

  scope.ContainerGUIPagination = Object.freeze({ pageCount, visiblePages });
})(globalThis);
