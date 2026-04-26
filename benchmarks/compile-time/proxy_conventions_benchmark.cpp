#include <proxy/proxy.h>
#include <cctype>

#ifndef CT_BENCHMARK_CONVENTION_NUMBER
# define CT_BENCHMARK_CONVENTION_NUMBER 3
#endif

template <size_t N> struct TypeGenerator {};

// Generate a facade with N conventions.
template <size_t N>
struct LongConventionFacade {
    using pre_type = typename LongConventionFacade<N-1>::type;
    using type = typename pre_type::template add_convention<
        pro::operator_dispatch<"<<", true>, void(TypeGenerator<N>)>;
};
template <>
struct LongConventionFacade<0> { using type = pro::facade_builder; };

struct TestFacade
: LongConventionFacade<CT_BENCHMARK_CONVENTION_NUMBER>::type::build {};

int main() {
    pro::proxy<TestFacade> p;
    (void)p;
}

