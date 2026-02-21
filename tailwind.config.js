/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html', './renderer/**/*.{vue,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        theme: {
          body: '#101014',
          card: '#18181c',
          input: '#27272a',
          border: '#2e2e32',
          accent: '#3b82f6',
          text: {
            primary: '#e4e4e7',
            secondary: '#a1a1aa',
            muted: '#52525b'
          }
        }
      },
      fontFamily: {
        mono: ['"JetBrains Mono"', 'monospace'],
        sans: ['Inter', 'sans-serif']
      }
    }
  },
  plugins: []
}
