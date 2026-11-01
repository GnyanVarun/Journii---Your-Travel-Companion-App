import { withLambda } from "@netlify/aws-lambda-compat";
import serverless from "serverless-http";
import app from "../../index.js";

const lambdaHandler = serverless(app);

export default withLambda(lambdaHandler);