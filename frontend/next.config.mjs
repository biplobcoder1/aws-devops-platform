/** @type {import('next').NextConfig} */
const nextConfig = {
  // "standalone" bundles only the files needed to run -> Docker image ~150MB instead of ~1GB
  output: "standalone",
  poweredByHeader: false,
};

export default nextConfig;
