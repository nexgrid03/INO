/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // react-pdf pulls in `canvas` for Node; we only ever render PDFs on the
  // client (DocViewer is dynamically imported with ssr:false), so stub it out
  // for the server build to avoid a native dependency.
  webpack: (config) => {
    config.resolve.alias = { ...config.resolve.alias, canvas: false };
    return config;
  },
};

module.exports = nextConfig;
