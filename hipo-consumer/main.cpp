#include <cmath>
#include <cstdio>

#include "Highs.h"

int main(int argc, char** argv) {
  Highs highs;
  if (argc != 2 || highs.readModel(argv[1]) != HighsStatus::kOk) {
    printf("FAIL: could not read the model\n");
    return 1;
  }
  highs.setOptionValue("presolve", "off");
  if (highs.setOptionValue("solver", "hipo") != HighsStatus::kOk) {
    printf("FAIL: solver=hipo was rejected\n");
    return 1;
  }
  const HighsStatus status = highs.run();
  const HighsInfo& info = highs.getInfo();
  printf("ipm_iterations=%d objective=%.7f\n", (int)info.ipm_iteration_count,
         info.objective_function_value);
  if (status != HighsStatus::kOk || info.ipm_iteration_count <= 0 ||
      highs.getModelStatus() != HighsModelStatus::kOptimal ||
      std::fabs(info.objective_function_value + 464.7531428) >= 1e-5) {
    printf("FAIL: HiPO did not produce the expected solution\n");
    return 1;
  }
  return 0;
}
