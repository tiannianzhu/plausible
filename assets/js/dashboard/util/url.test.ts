import {
  apiPath,
  internalApiPath,
  siteBasePath,
  sitePath,
  externalLinkForPage,
  isValidHttpUrl,
  trimURL
} from './url'
import { siteContextDefaultValue } from '../site-context'

describe('apiPath', () => {
  it.each([
    [{ id: 1 }, undefined, '/api/stats/s/1/'],
    [{ id: 1 }, '', '/api/stats/s/1/'],
    [{ id: 1 }, '/test', '/api/stats/s/1/test/']
  ])(
    'when site is %p and path is %s, should return %s',
    (site, path, expected) => {
      const result = apiPath(site, path)
      expect(result).toBe(expected)
    }
  )
})

describe('internalApiPath', () => {
  it.each([
    [{ id: 1 }, '', '/api/s/1'],
    [{ id: 1 }, '/segments', '/api/s/1/segments']
  ])(
    'when site is %p and path is %s, should return %s',
    (site, path, expected) => {
      const result = internalApiPath(site, path)
      expect(result).toBe(expected)
    }
  )
})

describe('site paths', () => {
  it.each([
    [{ id: 1, domain: 'example.com', shared: false }, '/s/1'],
    [
      { id: 3, domain: 'example.com/path/is-really/deep', shared: false },
      '/s/3'
    ],
    [{ id: 1, domain: 'example.com', shared: true }, '/share/example.com']
  ])('siteBasePath for %p returns %s', (site, expected) => {
    expect(siteBasePath(site)).toBe(expected)
  })

  it('appends dashboard subpaths to id-based site paths', () => {
    expect(
      sitePath({ id: 1, domain: 'example.com', shared: false }, '/settings')
    ).toBe('/s/1/settings')
  })
})

describe('externalLinkForPage', () => {
  it.each([
    ['example.com', '/about', 'https://example.com/about'],
    ['sub.example.com', '/contact', 'https://sub.example.com/contact'],
    [
      'example.com',
      '/search?q=test#section',
      'https://example.com/search?q=test#section'
    ],
    ['example.com', '/', 'https://example.com/']
  ])(
    'when domain is %s and page is %s, it should return %s',
    (domain, page, expected) => {
      const site = { ...siteContextDefaultValue, domain: domain }
      const result = externalLinkForPage(site, page)
      expect(result).toBe(expected)
    }
  )

  it('returns null for consolidated view', () => {
    const consolidatedView = {
      ...siteContextDefaultValue,
      isConsolidatedView: true
    }
    expect(externalLinkForPage(consolidatedView, '/some-page')).toBe(null)
  })
})

describe('isValidHttpUrl', () => {
  it.each([
    // Valid HTTP and HTTPS URLs
    ['http://example.com', true],
    ['https://example.com', true],
    ['http://www.example.com', true],
    ['https://sub.domain.com', true],
    ['https://example.com/path?query=1#fragment', true],

    // Invalid URLs (invalid protocol)
    ['ftp://example.com', false],
    ['mailto:someone@example.com', false],
    ['file:///C:/path/to/file', false],
    ['data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==', false],

    // Invalid URLs (malformed or non-URL strings)
    ['//example.com', false],
    ['example.com', false],
    ['just-a-string', false],
    ['', false],
    ['https//:example.com', false],

    // Edge cases
    ['http:/example.com', true],
    ['http://localhost', true],
    ['https://127.0.0.1', true],
    ['https://[::1]', true], // IPv6 URL
    ['http://user:pass@127.0.0.1', true],
    ['https://example.com:8080', true]
  ])('for input %s returns %s', (input, expected) => {
    const result = isValidHttpUrl(input)
    expect(result).toBe(expected)
  })
})

describe('trimURL', () => {
  it.each([
    // Test cases where URL length is less than or equal to maxLength
    ['https://example.com', 20, 'https://example.com'],
    ['http://example.com', 50, 'http://example.com'],

    // Test cases where host itself is too long
    [
      'https://a-very-long-domain-name.com',
      20,
      'https://a-very-long-dom...domain-name.com'
    ]
  ])(
    'when url is %s and maxLength is %d, should return %s',
    (url, maxLength, expected) => {
      const result = trimURL(url, maxLength)
      expect(result).toBe(expected)
    }
  )
})
