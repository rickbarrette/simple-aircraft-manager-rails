import { Controller } from "@hotwired/stimulus"

// Loading calculator: takeoff and landing weight and CG from the empty
// weight & moment plus each station's load, checked against max gross weight,
// station maximums and the CG envelope (drawn as a small chart).
export default class extends Controller {
  static targets = [ "station", "burn", "takeoffWeight", "takeoffCg", "takeoffMoment", "landingWeight", "landingCg", "landingMoment", "messages", "chart" ]
  static values = { emptyWeight: Number, emptyMoment: Number, maxGross: Number, fuelDensity: Number, envelope: Array }

  connect() { this.update() }

  update() {
    const messages = []
    let weight = this.emptyWeightValue
    let moment = this.emptyMomentValue
    let fuelArmMoment = 0
    let fuelGallons = 0
    this.stationTargets.forEach((input) => {
      const qty = parseFloat(input.value) || 0
      const arm = parseFloat(input.dataset.arm)
      const fuel = input.dataset.fuel === "true"
      const max = parseFloat(input.dataset.max) || 0
      const label = input.closest("label").querySelector(".label").firstChild.textContent.trim()
      if (max && qty > max) messages.push([ "bad", `${label}: ${qty} is over its maximum of ${max} ${fuel ? "gal" : "lb"}.` ])
      const lbs = fuel ? qty * this.fuelDensityValue : qty
      weight += lbs
      moment += lbs * arm
      if (fuel) { fuelArmMoment += qty * arm; fuelGallons += qty }
    })

    // Landing: burn fuel from the tanks at their average arm.
    const burn = Math.min(this.hasBurnTarget ? parseFloat(this.burnTarget.value) || 0 : 0, fuelGallons)
    const fuelArm = fuelGallons ? fuelArmMoment / fuelGallons : 0
    const landingWeight = weight - burn * this.fuelDensityValue
    const landingMoment = moment - burn * this.fuelDensityValue * fuelArm

    const takeoff = { weight, moment, cg: moment / weight }
    const landing = { weight: landingWeight, moment: landingMoment, cg: landingMoment / landingWeight }
    this.show("takeoff", takeoff)
    this.show("landing", landing)

    if (this.maxGrossValue && takeoff.weight > this.maxGrossValue) {
      messages.push([ "bad", `Takeoff weight is ${(takeoff.weight - this.maxGrossValue).toFixed(1)} lb over the maximum of ${this.maxGrossValue} lb.` ])
    }
    if (this.envelopeValue.length >= 3) {
      for (const [ name, point ] of [ [ "Takeoff", takeoff ], [ "Landing", landing ] ]) {
        if (!this.inside(point)) messages.push([ "bad", `${name} CG ${point.cg.toFixed(2)} in at ${point.weight.toFixed(0)} lb is outside the envelope.` ])
      }
    }
    if (!messages.length) messages.push([ "ok", "Within the limits entered here." ])
    this.messagesTarget.replaceChildren(...messages.map(([ kind, text ]) => {
      const li = document.createElement("li")
      li.className = kind === "ok" ? "text-emerald-700" : "text-red-700"
      li.textContent = text
      return li
    }))
    this.draw(takeoff, landing)
  }

  show(prefix, p) {
    this[`${prefix}WeightTarget`].textContent = `${p.weight.toFixed(1)} lb`
    this[`${prefix}CgTarget`].textContent = `${p.cg.toFixed(2)} in`
    this[`${prefix}MomentTarget`].textContent = Math.round(p.moment).toLocaleString()
  }

  // Ray casting: is the (cg, weight) point inside the envelope polygon?
  inside({ cg, weight }) {
    const pts = this.envelopeValue
    let inside = false
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const [ wi, ci ] = pts[i]
      const [ wj, cj ] = pts[j]
      if ((wi > weight) !== (wj > weight) && cg < ((cj - ci) * (weight - wi)) / (wj - wi) + ci) inside = !inside
    }
    return inside
  }

  draw(takeoff, landing) {
    const pts = this.envelopeValue
    const svg = this.chartTarget
    svg.replaceChildren()
    if (pts.length < 3) return
    const cgs = [ ...pts.map((p) => p[1]), takeoff.cg, landing.cg ]
    const ws = [ ...pts.map((p) => p[0]), takeoff.weight, landing.weight ]
    const [ cMin, cMax, wMin, wMax ] = [ Math.min(...cgs), Math.max(...cgs), Math.min(...ws), Math.max(...ws) ]
    const x = (c) => 15 + ((c - cMin) / (cMax - cMin || 1)) * 190
    const y = (w) => 145 - ((w - wMin) / (wMax - wMin || 1)) * 130
    const ns = "http://www.w3.org/2000/svg"
    const poly = document.createElementNS(ns, "polygon")
    poly.setAttribute("points", pts.map(([ w, c ]) => `${x(c)},${y(w)}`).join(" "))
    poly.setAttribute("class", "fill-sky-100 stroke-sky-600")
    svg.append(poly)
    for (const [ p, cls ] of [ [ takeoff, "fill-slate-900" ], [ landing, "fill-slate-400" ] ]) {
      const dot = document.createElementNS(ns, "circle")
      dot.setAttribute("cx", x(p.cg)); dot.setAttribute("cy", y(p.weight)); dot.setAttribute("r", 4); dot.setAttribute("class", cls)
      svg.append(dot)
    }
  }
}
