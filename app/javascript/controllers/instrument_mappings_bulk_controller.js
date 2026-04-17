import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "holdingIds", "holdingIdsExclude", "approveButton", "excludeButton"]

  connect() {
    this.selectedHoldingIds = new Set()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = checked
      this.updateSelectionFromCheckbox(checkbox)
    })
    this.updateFormFields()
  }

  updateSelection(event) {
    this.updateSelectionFromCheckbox(event.target)
    this.updateFormFields()
  }

  updateSelectionFromCheckbox(checkbox) {
    const holdingId = checkbox.value
    if (checkbox.checked) {
      this.selectedHoldingIds.add(holdingId)
    } else {
      this.selectedHoldingIds.delete(holdingId)
    }
  }

  updateFormFields() {
    const holdingIdsArray = Array.from(this.selectedHoldingIds)

    // Update both forms
    this.holdingIdsTargets.forEach(target => {
      target.innerHTML = this.buildHiddenFields(holdingIdsArray, "holding_ids[]")
    })

    this.holdingIdsExcludeTargets.forEach(target => {
      target.innerHTML = this.buildHiddenFields(holdingIdsArray, "holding_ids[]")
    })

    // Update button states
    const hasSelection = this.selectedHoldingIds.size > 0
    if (this.hasApproveButtonTarget) {
      this.approveButtonTarget.disabled = !hasSelection
    }
    if (this.hasExcludeButtonTarget) {
      this.excludeButtonTarget.disabled = !hasSelection
    }
  }

  buildHiddenFields(values, name) {
    return values.map(value =>
      `<input type="hidden" name="${name}" value="${value}">`
    ).join("")
  }

  validateSelection(event) {
    if (this.selectedHoldingIds.size === 0) {
      event.preventDefault()
      alert("Please select at least one holding to perform this action.")
      return false
    }
    return true
  }
}
