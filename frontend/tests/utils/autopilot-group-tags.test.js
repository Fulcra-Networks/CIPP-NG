import { describe, it, expect } from 'vitest'
import {
  buildGroupTagOptions,
  splitGroupTags,
  validateGroupTagOption,
  CLEAR_GROUP_TAG_OPTION,
  MISSING_GROUP_TAG_VALUE,
} from '../../src/utils/autopilot-group-tags'

// CippAutocomplete hands dataFilter one converted option per custom variable, with the API row in rawData.
const variable = (Name, Value) => ({ label: Name, value: Name, rawData: { Name, Value } })

describe('splitGroupTags', () => {
  it('trims, drops empties and dedupes', () => {
    expect(splitGroupTags(' ManagedPC, BLY ,,BLY-Shared,BLY ')).toEqual(['ManagedPC', 'BLY', 'BLY-Shared'])
  })

  it('reads a list-typed variable (stored as a JSON array)', () => {
    expect(splitGroupTags('["ManagedPC"," PAL ","PAL"]')).toEqual(['ManagedPC', 'PAL'])
  })

  it('returns nothing for a missing value', () => {
    expect(splitGroupTags(undefined)).toEqual([])
  })
})

describe('buildGroupTagOptions', () => {
  it('turns the AutopilotGroupTags variable into one option per tag, after a clear option', () => {
    const options = buildGroupTagOptions([
      variable('tenantname', 'Contoso'),
      variable('AutopilotGroupTags', 'ManagedPC,Administrator,Standard'),
    ])
    expect(options).toEqual([
      CLEAR_GROUP_TAG_OPTION,
      { label: 'ManagedPC', value: 'ManagedPC' },
      { label: 'Administrator', value: 'Administrator' },
      { label: 'Standard', value: 'Standard' },
    ])
  })

  it('offers only a hint when the tenant has no list', () => {
    const options = buildGroupTagOptions([variable('tenantname', 'Contoso')])
    expect(options).toHaveLength(1)
    expect(options[0].value).toBe(MISSING_GROUP_TAG_VALUE)
    expect(options[0].label).toMatch(/AutopilotGroupTags/)
  })

  it('ignores other variables, whatever their value', () => {
    expect(buildGroupTagOptions([variable('SomethingElse', 'A,B')])[0].value).toBe(MISSING_GROUP_TAG_VALUE)
  })
})

describe('validateGroupTagOption', () => {
  it('accepts a listed tag, the current tag and the clear option', () => {
    expect(validateGroupTagOption({ label: 'BLY', value: 'BLY' })).toBe(true)
    expect(validateGroupTagOption(CLEAR_GROUP_TAG_OPTION)).toBe(true)
  })

  it('rejects no selection and the hint option', () => {
    expect(validateGroupTagOption(null)).toMatch(/Select/)
    expect(validateGroupTagOption({ value: MISSING_GROUP_TAG_VALUE })).toMatch(/no group tag list/)
  })

  it('rejects tags over 128 characters', () => {
    expect(validateGroupTagOption({ value: 'x'.repeat(129) })).toMatch(/128/)
  })
})
