// Solve an MPS file with HiGHS through OR-Tools' MPSolver, passing HiGHS
// options through, and print the result in the same format as
// ortools/linear_solver/solve so ortools/check_log.py can check either.
//
// Usage: highs_check <model.mps> ["highs_option=value,..."]
//
// ortools/linear_solver/solve cannot be used for this: with --params it
// CHECK-fails because HighsInterface::SetSolverSpecificParametersAsString()
// returns false. The string is still stored and forwarded to HiGHS on
// Solve(), so the return value is ignored here.

#include <cstdio>
#include <string>

#include "absl/status/statusor.h"
#include "ortools/linear_solver/linear_solver.h"
#include "ortools/linear_solver/linear_solver.pb.h"
#include "ortools/lp_data/mps_reader.h"

using operations_research::MPModelProto;
using operations_research::MPSolver;

int main(int argc, char** argv) {
  if (argc < 2 || argc > 3) {
    std::fprintf(stderr, "usage: %s <model.mps> [highs_options]\n", argv[0]);
    return 2;
  }
  const std::string mps_file = argv[1];
  const std::string highs_options = argc == 3 ? argv[2] : "";

  absl::StatusOr<MPModelProto> model =
      operations_research::glop::MpsFileToMPModelProto(mps_file);
  if (!model.ok()) {
    std::fprintf(stderr, "Failed to read %s: %s\n", mps_file.c_str(),
                 std::string(model.status().message()).c_str());
    return 1;
  }

  MPSolver solver("highs_check", MPSolver::HIGHS_LINEAR_PROGRAMMING);
  std::string error;
  if (solver.LoadModelFromProto(*model, &error) !=
      operations_research::MPSOLVER_MODEL_IS_VALID) {
    std::fprintf(stderr, "Invalid model: %s\n", error.c_str());
    return 1;
  }
  solver.EnableOutput();
  if (!highs_options.empty()) {
    solver.SetSolverSpecificParametersAsString(highs_options);
  }

  std::printf("%-12s: %s\n", "Solver", solver.SolverVersion().c_str());
  std::printf("%-12s: %s\n", "Parameters", highs_options.c_str());
  const MPSolver::ResultStatus status = solver.Solve();
  const bool optimal = status == MPSolver::OPTIMAL;
  std::printf("%-12s: %s\n", "Status", optimal ? "OPTIMAL" : "NOT_OPTIMAL");
  std::printf("%-12s: %d\n", "ResultCode", static_cast<int>(status));
  std::printf("%-12s: %15.15e\n", "Objective",
              optimal ? solver.Objective().Value() : 0.0);
  std::fflush(stdout);
  return optimal ? 0 : 1;
}
