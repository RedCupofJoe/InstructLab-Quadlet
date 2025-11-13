"""
Simple SDG Hub dashboard.

What it does:
- Checks if sdg_hub can be imported
- Shows sdg_hub version (if available)
- Provides a button to run a tiny "smoke test" that exercises sdg_hub.

This is not a full UI, just a quick "is SDG alive and usable?" check.
"""

import traceback

import gradio as gr

# Try to import sdg_hub and get a version if present
try:
    import sdg_hub
    SDG_IMPORT_OK = True
    SDG_VERSION = getattr(sdg_hub, "__version__", "unknown")
except Exception as e:
    SDG_IMPORT_OK = False
    SDG_VERSION = f"import failed: {e}"


def status():
    """
    Basic status function to show in the dashboard.
    """
    if not SDG_IMPORT_OK:
        return (
            "❌ sdg_hub import FAILED\n\n"
            f"Details: {SDG_VERSION}\n\n"
            "Check that the container has sdg-hub installed."
        )

    msg = [
        "✅ sdg_hub import OK",
        f"Version: {SDG_VERSION}",
        "",
        "You can now run the smoke test below to confirm SDG Hub can do basic work.",
    ]
    return "\n".join(msg)


def smoke_test():
    """
    Very small functional test.

    We keep it intentionally simple so it:
    - Doesn't require a specific flow YAML
    - Only checks that sdg_hub core pieces work
    """
    if not SDG_IMPORT_OK:
        return (
            "❌ Cannot run smoke test because sdg_hub failed to import.\n\n"
            f"Import error: {SDG_VERSION}"
        )

    try:
        # Example: import a core block and instantiate something trivial
        from sdg_hub.core.blocks.base import BaseBlock

        class NoOpBlock(BaseBlock):
            """
            Minimal no-op block that just returns the input batch.
            This proves core sdg_hub interfaces are usable.
            """

            def forward(self, batch):
                return batch

        block = NoOpBlock(block_name="noop_block")
        sample_batch = {"text": ["hello sdg_hub", "this is a test"]}

        result = block.forward(sample_batch)

        return (
            "✅ Smoke test PASSED\n\n"
            "Created and executed a simple NoOpBlock from sdg_hub.\n\n"
            f"Input batch:  {sample_batch}\n"
            f"Output batch: {result}"
        )

    except Exception as e:
        tb = traceback.format_exc()
        return (
            "❌ Smoke test FAILED\n\n"
            f"Error: {e}\n\n"
            f"Traceback:\n{tb}"
        )


with gr.Blocks(title="SDG Hub Status Dashboard") as demo:
    gr.Markdown(
        """
# SDG Hub Status Dashboard

Use this page to quickly confirm that **SDG Hub is installed and working**
inside the container.

- ✅ **Status** shows whether `sdg_hub` imports and its version.
- 🧪 **Smoke Test** runs a tiny no-op block to confirm basic functionality.
        """
    )

    with gr.Row():
        status_button = gr.Button("Check Status")
        smoke_button = gr.Button("Run Smoke Test")

    status_output = gr.Textbox(
        label="Status",
        lines=8,
        interactive=False,
    )
    smoke_output = gr.Textbox(
        label="Smoke Test Result",
        lines=16,
        interactive=False,
    )

    status_button.click(fn=status, outputs=status_output)
    smoke_button.click(fn=smoke_test, outputs=smoke_output)


if __name__ == "__main__":
    # Launch on 0.0.0.0:9000 so the quadlet can map it to localhost
    demo.launch(server_name="0.0.0.0", server_port=9000)
