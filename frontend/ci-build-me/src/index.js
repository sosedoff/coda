const github = require("./util/github");
const HTTPError = require("./util/httpError");

const { httpsRequest } = require("./util/httpsRequest");
const axios = require("axios");

const apiKey = process.env.BUILDKITE_API_ACCESS_TOKEN;

const runBuild = async (github) => {
  const postData = JSON.stringify({
    commit: github.pull_request.head.sha,
    branch: github.pull_request.head.ref,
    ignore_pipeline_branch_filters: true,
    author: {
      name: github.sender.login,
    },
    pull_request_base_branch: github.pull_request.base.ref,
    pull_request_id: github.pull_request.number,
  });

  const options = {
    hostname: "api.buildkite.com",
    port: 443,
    path: `/v2/organizations/o-1-labs-2/pipelines/coda/builds`,
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(postData),
    },
  };
  const request = await httpsRequest(options, postData);
  return request;
};

const getRequest = async (url) => {
  const request = await axios.get(url);
  if (request.status < 200 || request.status >= 300) {
    throw new HTTPError(request.status);
  }
  return request;
};

const handler = async (event, req) => {
  const buildkiteTrigger = {};
  let request;
  if (event == "pull_request") {
    if (
      // if PR has ci-build-me label
      req.body.pull_request.labels.filter(
        (label) => label.name == "ci-build-me"
      ).length > 0 &&
      // and we are pushing new commits or actively adding this label
      (req.body.action == "synchronize" || req.body.action == "labeled") &&
      // and this is PR _not_ from a fork
      req.body.pull_request.head.user.login ==
        req.body.pull_request.base.user.login
    ) {
      request = await runBuild(req.body);
      return request;
    }
  } else if (event == "issue_comment") {
    if (
      // we are creating the comment
      req.body.action == "created" &&
      // and this is actually a pull request
      req.body.issue.pull_request &&
      req.body.issue.pull_request.url &&
      // and the comment contents is exactly the slug we are looking for
      req.body.comment.body == "!ci-build-me"
    ) {
      const orgData = await getRequest(req.body.sender.organizations_url);
      // and the comment author is part of the core team
      if (
        orgData.data.filter((org) => org.login == "CodaProtocol").length > 0
      ) {
        const prData = await getRequest(req.body.issue.pull_request.url);
        const request = await runBuild({
          sender: req.body.sender,
          pull_request: prData.data,
        });
        return request;
      }
    }
  }
  return null;
};

/**
 * HTTP Cloud Function for GitHub Webhook events.
 *
 * @param {object} req Cloud Function request context.
 * @param {object} res Cloud Function response context.
 */
exports.githubWebhookHandler = async (req, res) => {
  try {
    if (!req || !res || !req.method) {
      throw new HTTPError(400);
    }

    if (req.method !== "POST") {
      console.info(
        `Rejected ${req.method} request from ${req.ip} (${req.headers["user-agent"]})`
      );
      throw new HTTPError(405, "Only POST requests are accepted");
    }
    console.info(
      `Received request from ${req.ip} (${req.headers["user-agent"]})`
    );

    // Verify that this request came from GitHub
    github.validateWebhook(req);

    const githubEvent = req.headers["x-github-event"];
    const request = await handler(githubEvent, req);
    if (request && request.web_url) {
      console.info(`Triggered build at ${request.web_url}`);
    } else {
      console.error("Failed to trigger build for some reason:");
      console.error(request);
    }

    res.status(200);
    console.info(`HTTP 200: ${githubEvent} event`);
    res.send(request || {});
  } catch (e) {
    if (e instanceof HTTPError) {
      res.status(e.statusCode).send(e.message);
      console.info(`HTTP ${e.statusCode}: ${e.message}`, e);
    } else {
      res.status(500).send(e.message);
      console.error(`HTTP 500: ${e.message}`);
    }
  }
};
