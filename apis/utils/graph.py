# -*- coding: utf-8 -*-
import io
from dataclasses import dataclass

import matplotlib.pyplot as plt
import numpy as np


@dataclass
class LineChartData:
    """
    The struct of line for plotting
    """

    name: str
    x: list
    y: list
    style: str = ""

    def validate(self):
        ret = True
        for field_name, field_def in self.__dataclass_fields__.items():
            actual_type = type(getattr(self, field_name))
            if actual_type != field_def.type:
                print(
                    f"\t{field_name}: '{actual_type}' instead of '{field_def.type}'"
                )
                ret = False
        return ret

    def __post_init__(self):
        if not self.validate():
            raise ValueError("Wrong types")


def draw_line_chart(*lines, xlabel=None, ylabel=None, fmt="PNG", title=None):
    """
    A line chart maker by matplotlib.pyplot

    Args:
        # #line: a serial of LineChartData object
        # xlabel: A label of X-axis
        # ylabel: A label of Y-axis
        # fmt: a kind of output format

    Returns:
        return io.BytesIO object

    Raises:
        None

    Example:
        def sample:
            l1 = LineChartData(
                "TEST_LINE_1",
                [1, 2, 3, 4, 5],
                [0.5, 1.0, 1.5, 2.0, 2.5],
            )
            l2 = LineChartData(
                "TEST_LINE_2",
                [1, 2, 3, 4, 5],
                [5.5, 3.5, 4.55, 0.05, 2.55],
                style='--',
            )
            lines = [l1, l2]

            png = draw_line_chart(
                *lines, xlabel="X_LABEL", ylabel="Y_LABEL", title="SAMPLE",
            )
            allure.attach(
                png.getvalue(),
                attachment_type=allure.attachment_type.PNG,
                name="Attach to report",
            )
    """
    for line in lines:
        plt.plot(
            np.array(line.x),
            np.array(line.y),
            line.style,
            label=line.name,
        )
    plt.legend()
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    if title:
        plt.title(title)

    figure = io.BytesIO()
    plt.savefig(figure, format=fmt)
    plt.close()
    return figure
