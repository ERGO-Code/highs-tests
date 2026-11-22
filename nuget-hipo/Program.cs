// Solves a small LP with the Highs.Native NuGet package. Argument "with": the
// Extras package is installed, so HiPO must solve it. "without": selecting HiPO
// must be rejected, and the other IPM must still solve it.
using System;
using Highs;

class Program {
  static int Fail(string message) {
    Console.WriteLine("FAIL: " + message);
    return 1;
  }

  static int Main(string[] args) {
    if (args.Length != 1 || (args[0] != "with" && args[0] != "without"))
      return Fail("usage: with | without");
    bool extras = args[0] == "with";

    // min -x0 - x1  s.t.  x0 + 2x1 <= 4,  3x0 + x1 <= 6,  x >= 0
    double inf = 1.0e30;
    var model = new HighsModel(
        new double[] {-1, -1}, new double[] {0, 0}, new double[] {inf, inf},
        new double[] {-inf, -inf}, new double[] {4, 6},
        new int[] {0, 2}, new int[] {0, 1, 0, 1}, new double[] {1, 2, 3, 1},
        null, 0, HighsMatrixFormat.kRowwise, HighsObjectiveSense.kMinimize);
    var solver = new HighsLpSolver();
    solver.passLp(model);
    // Without presolve, so the IPM, not presolve, solves it
    solver.setStringOptionValue("presolve", "off");

    HighsStatus hipo = solver.setStringOptionValue("solver", "hipo");
    Console.WriteLine("solver=hipo: " + hipo);
    if (!extras) {
      if (hipo != HighsStatus.kError) return Fail("solver=hipo accepted without Extras");
      // IPX, the IPM in the base package, must still work without Extras
      solver.setStringOptionValue("solver", "ipm");
    } else if (hipo != HighsStatus.kOk) {
      return Fail("solver=hipo rejected with Extras");
    }

    HighsStatus status = solver.run();
    var info = solver.getInfo();
    Console.WriteLine("status=" + status + " model_status=" + solver.GetModelStatus() +
                      " ipm_iterations=" + info.IpmIterationCount + " objective=" + info.ObjectiveValue);
    if (status != HighsStatus.kOk || solver.GetModelStatus() != HighsModelStatus.kOptimal ||
        info.IpmIterationCount <= 0 || Math.Abs(info.ObjectiveValue + 2.8) >= 1e-6)
      return Fail("not the expected IPM solution");
    Console.WriteLine("PASS");
    return 0;
  }
}
