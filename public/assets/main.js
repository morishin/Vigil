const keepAwake = document.getElementById("keep-awake");
keepAwake.addEventListener("change", () => {
  document.body.classList.toggle("snuffed", !keepAwake.checked);
});
