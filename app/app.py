import logging
import os
import uuid

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from flask import Flask, render_template, request

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BUCKET_NAME = os.environ.get("DOCUMENT_BUCKET_NAME", "")
s3_client = boto3.client("s3")


@app.route("/", methods=["GET"])
def index():
    return render_template("index.html", message=None, status=None)


@app.route("/health", methods=["GET"])
def health():
    # Deliberately does not check S3/RDS reachability — this is a liveness check for the
    # Flask process itself, so a transient AWS blip does not cause the ALB to cycle
    # healthy instances.
    return {"status": "ok"}, 200


@app.route("/upload", methods=["POST"])
def upload():
    uploaded_file = request.files.get("file")

    if uploaded_file is None or uploaded_file.filename == "":
        return render_template(
            "index.html",
            status="error",
            message="Please select a file before uploading.",
        ), 400

    # No file-size or file-type restriction is enforced here — a deliberate, documented
    # MVP scope cut (spec.md FR-016, clarified 2026-09-27). Any file/size is accepted.
    object_key = f"uploads/{uuid.uuid4()}-{uploaded_file.filename}"

    try:
        s3_client.upload_fileobj(
            uploaded_file,
            BUCKET_NAME,
            object_key,
            ExtraArgs={"ContentType": uploaded_file.content_type or "application/octet-stream"},
        )
    except (BotoCoreError, ClientError):
        logger.exception("Failed to upload object to S3: key=%s", object_key)
        return render_template(
            "index.html",
            status="error",
            message="Upload failed. Please try again.",
        ), 502

    logger.info("Uploaded object to S3: key=%s", object_key)
    return render_template(
        "index.html",
        status="success",
        message="Your document was uploaded successfully.",
    ), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
