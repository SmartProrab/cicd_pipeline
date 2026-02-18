module.exports = {
    branches: [
        "main",
        { name: "beta", prerelease: true }
    ],
    tagFormat: "v${version}",
    plugins: [
        "@semantic-release/commit-analyzer",
        "@semantic-release/release-notes-generator",
        ["@semantic-release/exec", {
            prepareCmd: "echo ${nextRelease.version} > .release_version"
        }],
        "@semantic-release/github"
    ]
};
