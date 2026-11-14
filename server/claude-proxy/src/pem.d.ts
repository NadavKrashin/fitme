// wrangler bundles .pem files as text (see `rules` in wrangler.toml).
declare module "*.pem" {
  const text: string;
  export default text;
}

// Vite's raw import, for the tests.
declare module "*.pem?raw" {
  const text: string;
  export default text;
}
