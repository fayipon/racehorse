import { describe, expect, it } from 'vitest'
import { CUPS, type CupId } from './game'
import { LOCALES } from './locale'
import { parseRoute, routePath } from './route'

const BASE = '/racehorse/'

describe('addresses', () => {
  it('names the language first, then the cup', () => {
    expect(routePath('en', undefined, BASE)).toBe('/racehorse/en/')
    expect(routePath('pt-BR', 'royal', BASE)).toBe('/racehorse/pt-BR/royal/')
    expect(routePath('zh-TW', 'sunny', '/')).toBe('/zh-TW/sunny/')
  })

  it('reads back every page in every language', () => {
    for (const locale of LOCALES) {
      expect(parseRoute(routePath(locale, undefined, BASE), BASE)).toEqual({ locale, cup: undefined })
      for (const cup of Object.keys(CUPS) as CupId[]) expect(parseRoute(routePath(locale, cup, BASE), BASE)).toEqual({ locale, cup })
    }
  })

  it('matches a language in any letter case and page file names', () => {
    expect(parseRoute('/racehorse/zh-tw/thunder/', BASE)).toEqual({ locale: 'zh-TW', cup: 'thunder' })
    expect(parseRoute('/racehorse/JA/sunny/index.html', BASE)).toEqual({ locale: 'ja', cup: 'sunny' })
    expect(parseRoute('/racehorse/en', BASE)).toEqual({ locale: 'en', cup: undefined })
  })

  it('leaves the language out of addresses that have none', () => {
    expect(parseRoute('/racehorse/', BASE)).toEqual({ locale: undefined, cup: undefined })
    expect(parseRoute('/racehorse/royal/', BASE)).toEqual({ locale: undefined, cup: 'royal' })
    expect(parseRoute('/racehorse/fr/royal/', BASE)).toEqual({ locale: undefined, cup: undefined })
    expect(parseRoute('/racehorse/en/derby/', BASE)).toEqual({ locale: 'en', cup: undefined })
  })
})
