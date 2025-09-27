#!/usr/bin/env python3
from aws_cdk import App, Environment

from image_builder import ImageBuilderStack
from workstation_baseline import WorkstationBaseline

app = App()

# Baseline workstation infrastructure
WorkstationBaseline(
    app, "WorkstationBaseline", env=Environment(account="058264484340", region="us-east-1")
)

# Image Builder infrastructure for custom AMIs
ImageBuilderStack(app, "ImageBuilder", env=Environment(account="058264484340", region="us-east-1"))

app.synth()
