// https://github.com/jhukdev/gatsby-lambda/blob/main/webpack.config.js

const path = require('path');
const { BannerPlugin } = require('webpack');
const nodeExternals = require('webpack-node-externals');
const CopyPackage = require('copy-pkg-json-webpack-plugin');
const FileManagerPlugin = require('filemanager-webpack-plugin');

module.exports = {
  entry: {
    preview_function: "./src/preview_function.ts",
    helloworld_function: "./src/helloworld_function.ts",
  },
  mode: 'production',
  target: 'node',
  context: __dirname,
  resolve: {
    modules: [path.resolve(__dirname, 'node_modules')],
    extensions: ['*', '.mjs', '.ts', '.js', '.json', '.gql', '.graphql'],
    alias: {
      '@': path.resolve('./src'),
    },
  },
  node: {
    __dirname: false,
    __filename: false,
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        use: ['ts-loader'],
      },
    ],
  },
  plugins: [
    new CopyPackage({
      remove: ['devDependencies'],
      replace: { scripts: { start: 'node index.js' } },
      to: './dist/preview_function',
    }),
    new FileManagerPlugin({
      events: {
        onEnd: [{
            copy: [
                {
                  source: path.join(__dirname, 'dist/package.json'),
                  destination: path.join(__dirname, 'dist/preview_function/package.json')
                }
            ]
        }]
      }
    }),
    new BannerPlugin({
      banner: `
        process.env.NODE_ENV = 'production';
      `,
      raw: true,
    }),
  ],
  externals: [nodeExternals()],
  output: {
    libraryTarget: 'umd',
    path: path.resolve(__dirname, './dist'),
    filename: '[name]/index.js',
  },
  stats: {
    warnings: false,
  },
};