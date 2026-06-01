import { Controller } from "@hotwired/stimulus"

// Live-generates an SEO slug from one or more source fields and writes it
// to a target input. Stops auto-updating as soon as the user types in the
// slug field directly, so manual overrides are preserved.
//
// Source values are joined with spaces, then normalized:
//   * NFKD-folded to strip accents
//   * lowercased
//   * non-alphanumerics → hyphens
//   * runs collapsed, trims leading/trailing hyphens
//
// Usage:
//   <form data-controller="slug-generator">
//     <input data-slug-generator-target="source" data-action="input->slug-generator#regenerate">
//     <input data-slug-generator-target="source" data-action="input->slug-generator#regenerate">
//     <input data-slug-generator-target="slug" data-action="input->slug-generator#markEdited">
//   </form>
export default class extends Controller {
  static targets = ["source", "slug"]

  connect() {
    // If the slug field already has a value when the form mounts, assume
    // the user (or server) put it there on purpose.
    this._userEdited = this.hasSlugTarget && this.slugTarget.value.trim().length > 0
  }

  regenerate() {
    if (this._userEdited) return
    if (!this.hasSlugTarget) return
    const joined = this.sourceTargets.map((el) => el.value).join(" ")
    this.slugTarget.value = this.slugify(joined)
  }

  // Detect direct user input on the slug field, but only treat it as
  // "edited" if they actually deviate from what we'd generate. That way,
  // clicking into the field and tabbing back out doesn't lock the slug.
  markEdited() {
    if (!this.hasSlugTarget) return
    const joined = this.sourceTargets.map((el) => el.value).join(" ")
    const generated = this.slugify(joined)
    this._userEdited = this.slugTarget.value !== generated
  }

  slugify(s) {
    if (!s) return ""
    return s
      .normalize("NFKD")
      .replace(/[̀-ͯ]/g, "")  // strip combining marks
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .replace(/-{2,}/g, "-")
  }
}
