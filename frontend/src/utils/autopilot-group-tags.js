// Fulcra custom (migration plan 09): Autopilot group tags come from a curated per-tenant list
// instead of free text, because a mistyped tag silently drops the device out of its deployment
// profile. The list is the custom variable AutopilotGroupTags (comma separated), set globally
// and/or per tenant under Tenant > Custom Variables. ListCustomVariables returns the tenant's
// value when it has one, otherwise the global one.

export const AUTOPILOT_GROUP_TAG_VARIABLE = 'AutopilotGroupTags'

// Picking this clears the tag. The value is a single space, not '': CippAutocomplete treats an
// option whose value is '' as "nothing selected" and drops it, so the form saw an empty field.
// The endpoint trims the tag, so ' ' arrives as an empty tag.
export const CLEAR_GROUP_TAG_OPTION = { label: '(clear tag)', value: ' ' }

// Shown when the tenant has no list. Its value is rejected by validateGroupTagOption.
export const MISSING_GROUP_TAG_VALUE = '__no_group_tag_list__'

// A string variable holds 'A,B,C'; a list-typed variable is stored as the JSON array '["A","B"]'.
const parseGroupTagValue = (value) => {
  const text = String(value ?? '').trim()
  if (text.startsWith('[')) {
    try {
      const parsed = JSON.parse(text)
      if (Array.isArray(parsed)) return parsed.map(String)
    } catch {
      // Not JSON after all: fall through to the comma split.
    }
  }
  return text.split(',')
}

export const splitGroupTags = (value) => [
  ...new Set(
    parseGroupTagValue(value)
      .map((tag) => tag.trim())
      .filter(Boolean)
  ),
]

// dataFilter for CippAutocomplete: receives one converted option per custom variable and
// returns one option per tag in the AutopilotGroupTags variable.
export const buildGroupTagOptions = (variableOptions) => {
  const variable = (variableOptions ?? []).find(
    (option) => option?.rawData?.Name === AUTOPILOT_GROUP_TAG_VARIABLE
  )
  const tags = splitGroupTags(variable?.rawData?.Value)
  if (tags.length === 0) {
    return [
      {
        label: `No group tag list for this tenant. Add the ${AUTOPILOT_GROUP_TAG_VARIABLE} custom variable (comma separated) under Tenant > Custom Variables.`,
        value: MISSING_GROUP_TAG_VALUE,
      },
    ]
  }
  return [CLEAR_GROUP_TAG_OPTION, ...tags.map((tag) => ({ label: tag, value: tag }))]
}

export const validateGroupTagOption = (option) => {
  const value = option?.value ?? option
  if (value === undefined || value === null) return 'Select a group tag.'
  if (value === MISSING_GROUP_TAG_VALUE) return 'This tenant has no group tag list yet.'
  if (String(value).length > 128) return 'Group tag cannot exceed 128 characters.'
  return true
}
