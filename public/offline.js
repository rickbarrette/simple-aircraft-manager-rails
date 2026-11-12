// The offline page: reload when the connection is back, and link to the Log
// Flight forms this device has kept (so a flight can be logged offline).
window.addEventListener("online", function () { location.reload() })
try {
  var forms = JSON.parse(localStorage.getItem("sam-offline-forms") || "{}")
  var box = document.getElementById("forms")
  Object.keys(forms).forEach(function (path) {
    if (!/^\/aircraft\/\d+\/flight_logs\/new$/.test(path)) return
    var a = document.createElement("a")
    a.href = path
    a.textContent = "Log a flight: " + forms[path]
    box.appendChild(a)
    box.hidden = false
  })
} catch (e) { /* storage off */ }
