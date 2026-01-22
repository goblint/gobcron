#! /usr/bin/env python3

# take first parameter as a filename
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys
from pathlib import Path

def main():
    weightedscores = True
    if len(sys.argv) < 2:
        print("Usage: stackedgraph.py <csvfile>")
        exit(1)
    csvfile = sys.argv[1]

    #prepare dataframe:
    df = []
    # use pandas to read csv file 
    df = pd.read_csv(csvfile)

    # sort by time
    df = df.sort_values(by=["cputime"])

    # select only rows where verdict is 'true'
    df = df[df["verdict"] == "true"]

    # select only columns 'time', 'portfoliolevel', 'verdict', 'overallweight'
    df = df[["cputime", "level", "verdict","overallweight"]]

    # output dataframe as a stacked graph using matplotlib
    configs = df["level"].unique()
    time = df["cputime"].unique()
    success_matrix = np.zeros((len(configs), len(time)))
    for i, config in enumerate(configs):
        for j, t in enumerate(time):
            if weightedscores:
                success_matrix[i][j] = df[(df["level"] == config) & (df["cputime"] <= t)]["overallweight"].sum()*2
            else:
                success_matrix[i][j] = df[(df["level"] == config) & (df["cputime"] <= t)]["verdict"].count()

    # make the time axis log scale
    plt.xscale("log")
    plt.gca().yaxis.set_label_position("right")
    plt.gca().yaxis.tick_right()
    plt.stackplot(time, success_matrix, labels=configs)
    plt.legend(loc='upper left')
    plt.xlabel('Time in secs')
    if weightedscores:
        plt.ylabel('Weighted Scores')
        plt.title('Stacked Weighted Scores over Time by Portfolio Level')
    else:
        plt.ylabel('True Verdicts')
        plt.title('Stacked True Verdicts over Time by Portfolio Level')
    output_dir = Path(csvfile).parent
    outputfile_svg = output_dir / (Path(csvfile).stem + "_stackedgraph.svg")
    plt.savefig(outputfile_svg)
    outputfile_png = output_dir / (Path(csvfile).stem + "_stackedgraph.png")
    plt.savefig(outputfile_png)

if __name__ == "__main__":
    main()