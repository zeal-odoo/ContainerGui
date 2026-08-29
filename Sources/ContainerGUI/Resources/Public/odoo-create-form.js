"use strict";

(function exposeOdooCreateForm(scope) {
  function imageRepository(reference) {
    let repository = String(reference || "");
    const digestSeparator = repository.indexOf("@");
    if (digestSeparator >= 0) repository = repository.slice(0, digestSeparator);
    const tagSeparator = repository.lastIndexOf(":");
    if (tagSeparator > repository.lastIndexOf("/")) repository = repository.slice(0, tagSeparator);
    return repository;
  }

  function isOfficialOdooImage(reference) {
    const repository = imageRepository(reference);
    return repository === "odoo" || repository === "docker.io/library/odoo";
  }

  function createFormMode(reference) {
    if (isOfficialOdooImage(reference)) {
      return {
        isOdoo: true,
        directoryLabel: "Odoo 自定义模块目录",
        directoryHelp: "本机目录会读写映射到 Odoo 官方自定义模块目录 /mnt/extra-addons。",
        containerPath: "/mnt/extra-addons",
        targetReadOnly: true,
        showDatabase: true
      };
    }
    return {
      isOdoo: false,
      directoryLabel: "本机共享目录",
      directoryHelp: "用于本机与容器之间读写和传输文件；留空则不挂载。",
      containerPath: "/workspace",
      targetReadOnly: false,
      showDatabase: false
    };
  }

  scope.ContainerGUIOdooCreateForm = Object.freeze({
    imageRepository,
    isOfficialOdooImage,
    createFormMode
  });
})(globalThis);
