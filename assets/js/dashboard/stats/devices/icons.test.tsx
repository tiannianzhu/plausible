import React from 'react'
import { render, screen } from '@testing-library/react'
import { BrowserIcon, OsIcon } from './icons'

beforeEach(() => {
  document.head.innerHTML =
    '<meta name="plausible-base-path" content="/hsp" />'
})

it('adds the application base path to browser and operating system icons', () => {
  render(
    <>
      <BrowserIcon dimensionValue="Chrome" />
      <OsIcon dimensionValue="Windows" />
    </>
  )

  const [browserIcon, operatingSystemIcon] = screen.getAllByRole('img')

  expect(browserIcon).toHaveAttribute(
    'src',
    '/hsp/images/icon/browser/chrome.svg'
  )
  expect(operatingSystemIcon).toHaveAttribute(
    'src',
    '/hsp/images/icon/os/windows.png'
  )
})
