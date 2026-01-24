import argparse
import pandas as pd

parser = argparse.ArgumentParser()
parser.add_argument("--currentcsv", help="Base path to the new results files, e.g. results/current")
parser.add_argument("--oldcsv", help="Path to the old results CSV file")
args = parser.parse_args()

print(f"Comparing current results in {args.currentcsv} to old results in {args.oldcsv}")

def decorate_diff(val):
    if val > 0:
        return f":trophy: (+{val})"
    elif val < 0:
        return f":wrong: ({val})"
    else:
        return ":check_mark: +/-0"

def compare_totalscore():
    current=pd.read_csv(args.currentcsv+"/totalscore.csv",header="infer", sep=",")
    old    =pd.read_csv(args.oldcsv    +"/totalscore.csv",header="infer", sep=",")
    # if table dimensions differ, something is wrong
    if current.shape != old.shape:
        print("Error: current and old totalscore.csv have different shapes!")
        print(f"Current shape: {current.shape}, old shape: {old.shape}")
        return
    oldhash="??"
    # read old tag from oldcsv/tag
    with open(args.oldcsv+"/commithash","r") as f:
        oldhash=f.read().strip()
    # drop Contrib column if exists in old
    if "Contrib" in old.columns:
        old = old.drop(columns=["Contrib","Score accum."])
    # join based on level, with only suffix for old
    merged = pd.merge(current, old, how="outer", on="level", suffixes=(None, '_old'), indicator=False)
    merged[":red_triangle_up: Score vs. "+oldhash] = merged["Score"] - merged["Score_old"]
    # map decorate_diff to the new column
    merged[":red_triangle_up: Score vs. "+oldhash] = merged[":red_triangle_up: Score vs. "+oldhash].apply(decorate_diff)
    merged = merged.drop(columns=["Score_old"])
    # move column Contrib to the end
    contrib = merged.pop("Contrib")
    merged["Contrib"] = contrib
    merged.to_markdown(args.currentcsv+"/totalscore_comparison.md", index=False)
    merged.to_csv(args.currentcsv+"/totalscore_comparison.csv", index=False)

def compare_percat():
    current=pd.read_csv(args.currentcsv+"/finalscorespercat.csv",header="infer", sep=",")
    old    =pd.read_csv(args.oldcsv    +"/finalscorespercat.csv",header="infer", sep=",")
    # if table dimensions differ, something is wrong
    if current.shape != old.shape:
        print("Error: current and old finalscorespercat.csv have different shapes!")
        print(f"Current shape: {current.shape}, old shape: {old.shape}")
        return
    oldhash="??"
    # read old tag from oldcsv/tag
    with open(args.oldcsv+"/commithash","r") as f:
        oldhash=f.read().strip()
    old.drop(columns=["Wrong"])
    merged = pd.merge(current, old, how="outer", on="metacategory", suffixes=(None, '_old'), indicator=False)
    merged[":red_triangle_up: verdict vs. "+oldhash] = merged["Verdicts"] - merged["Verdicts_old"]
    # move Wrong to the end
    wrong = merged.pop("Wrong")
    merged["Wrong"] = wrong
    # move Score to the end
    score = merged.pop("Score")
    merged["Score"] = score
    merged[":red_triangle_up: score vs. "+oldhash]         = merged["Score"] - merged["Score_old"]
    merged = merged.drop(columns=["Verdicts_old","Score_old","CPU time_old","Wrong_old"])
    # map decorate_diff to the new columns
    merged[":red_triangle_up: verdict vs. "+oldhash] = merged[":red_triangle_up: verdict vs. "+oldhash].apply(decorate_diff)
    merged[":red_triangle_up: score vs. "+oldhash]   = merged[":red_triangle_up: score vs. "+oldhash].apply(decorate_diff)
    # move column CPU time to the end
    cpu_time = merged.pop("CPU time")
    merged["CPU time"] = cpu_time
    merged.to_markdown(args.currentcsv+"/finalscorespercat_comparison.md", index=False)
    merged.to_csv(args.currentcsv+"/finalscorespercat_comparison.csv", index=False)

compare_totalscore()
compare_percat()