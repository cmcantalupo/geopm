/*
 * Copyright (c) 2015 - 2023, Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "gtest/gtest.h"
#include "gmock/gmock.h"
#include "geopm/Exception.hpp"
#include "geopm_test.hpp"

#include "TensorMath.hpp"
#include "TensorOneD.hpp"
#include "TensorTwoD.hpp"

using geopm::TensorMathImp;
using geopm::TensorOneD;
using geopm::TensorTwoD;

class TensorMathTest : public ::testing::Test
{
    protected:
        void SetUp();

        TensorOneD one, two, three;
        TensorMathImp math;
        TensorTwoD mat, row;
};

void TensorMathTest::SetUp()
{
    one.set_dim(2);
    two.set_dim(2);
    three.set_dim(3);

    one[0] = 1;
    one[1] = 2;
    two[0] = 3;
    two[1] = 4;
    three[0] = 0;
    three[1] = 1;
    three[2] = 1;

    mat.set_dim(2, 3);

    mat[0][0] = 1;
    mat[0][1] = 2;
    mat[0][2] = 3;
    mat[1][0] = 4;
    mat[1][1] = 5;
    mat[1][2] = 6;

    row.set_dim(1, 3);
    row[0][0] = 1;
    row[0][1] = 2;
    row[0][2] = 3;
}

TEST_F(TensorMathTest, test_sum)
{
    TensorOneD four = math.add(one, two);
    EXPECT_EQ(4, four[0]);
    EXPECT_EQ(6, four[1]);
}

TEST_F(TensorMathTest, test_self_sum)
{
    TensorOneD four = math.add(two, two);
    EXPECT_EQ(6, four[0]);
    EXPECT_EQ(8, four[1]);
}

TEST_F(TensorMathTest, test_diff)
{
    TensorOneD four = math.subtract(one, two);
    EXPECT_EQ(-2, four[0]);
    EXPECT_EQ(-2, four[1]);
}

TEST_F(TensorMathTest, test_self_diff)
{
    TensorOneD four = math.subtract(one, one);
    EXPECT_EQ(0, four[0]);
    EXPECT_EQ(0, four[1]);
}

TEST_F(TensorMathTest, test_dot)
{
    EXPECT_EQ(11, math.inner_product(one, two));
}

TEST_F(TensorMathTest, test_sigmoid)
{
    TensorOneD activations(5);

    activations[0] = -log(1/0.1 - 1);
    activations[1] = -log(1/0.25 - 1);
    activations[2] = -log(1/0.5 - 1);
    activations[3] = -log(1/0.75 - 1);
    activations[4] = -log(1/0.9 - 1);

    TensorOneD output = math.sigmoid(activations);

    EXPECT_FLOAT_EQ(0.1, output[0]);
    EXPECT_FLOAT_EQ(0.25, output[1]);
    EXPECT_FLOAT_EQ(0.5, output[2]);
    EXPECT_FLOAT_EQ(0.75, output[3]);
    EXPECT_FLOAT_EQ(0.9, output[4]);
}

TEST_F(TensorMathTest, test_mat_prod)
{
    TensorOneD prod = math.multiply(mat, row[0]);
    EXPECT_EQ(2u, prod.get_dim());
    EXPECT_EQ(14, prod[0]);
    EXPECT_EQ(32, prod[1]);
}

TEST_F(TensorMathTest, test_bad_dimensions)
{
    GEOPM_EXPECT_THROW_MESSAGE(math.add(one, three), GEOPM_ERROR_INVALID, "mismatched dimensions");
    GEOPM_EXPECT_THROW_MESSAGE(math.subtract(one, three), GEOPM_ERROR_INVALID, "mismatched dimensions");
    GEOPM_EXPECT_THROW_MESSAGE(math.inner_product(one, three), GEOPM_ERROR_INVALID, "mismatched dimensions");
    row.set_dim(1, 2);
    GEOPM_EXPECT_THROW_MESSAGE(math.multiply(mat, row[0]), GEOPM_ERROR_INVALID, "incompatible dimensions");
}
