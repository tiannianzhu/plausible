function normalizeBasePath(path: string | null | undefined): string {
  if (!path) {
    return ''
  }

  return path.endsWith('/') ? path.slice(0, -1) : path
}

export function getBasePath(): string {
  const meta = document.querySelector("meta[name='plausible-base-path']")
  return normalizeBasePath(meta?.getAttribute('content'))
}

export function withBasePath(path: string): string {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`
  return `${getBasePath()}${normalizedPath}`
}
