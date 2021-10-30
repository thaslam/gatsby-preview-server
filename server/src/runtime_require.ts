declare const __webpack_require__: any;
declare const __non_webpack_require__: any;

function runtimeRequire(path: string) {
  const requireFunction =
    typeof __webpack_require__ === 'function' ? __non_webpack_require__ : require;

  return requireFunction(path);
}

export { runtimeRequire };